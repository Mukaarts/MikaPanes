import AppKit
import SwiftUI

/// Backing state for the browser window: directory contents, fuzzy filter,
/// multi-selection, the system-pasteboard clipboard, navigation history, live
/// directory watching, undo, and the file actions triggered from keyboard,
/// menus and drag & drop.
@MainActor
final class FileBrowserModel: ObservableObject {

    struct Entry: Identifiable, Hashable, SortableEntry {
        let url: URL
        let name: String
        let isDirectory: Bool
        let isHidden: Bool
        let modificationDate: Date?
        let fileSize: Int64?
        var id: URL { url }
    }

    @Published var currentURL: URL
    @Published private(set) var entries: [Entry] = []
    @Published var query: String = "" {
        didSet { if query != oldValue { resetSelectionToFirstMatch() } }
    }
    @Published private(set) var selectedURLs: Set<URL> = []
    @Published private(set) var leadSelectionURL: URL?
    @Published var statusMessage: String?
    @Published private(set) var renamingURL: URL?
    @Published private(set) var cutPendingURLs: Set<URL> = []
    @Published private(set) var sortField: SortField
    @Published private(set) var sortAscending: Bool
    @Published private(set) var showHiddenFiles: Bool

    let favoritesStore: FavoritesStore
    let undoManager = UndoManager()

    /// Injected by the window layer: open a folder in a new window/tab.
    var openInNewWindow: ((URL) -> Void)?
    var openInNewTab: ((URL) -> Void)?

    private let settings: SettingsStore
    private var history = NavigationHistory()
    private var selectionAnchorURL: URL?
    private var watcher: DirectoryWatcher?
    private var loadGeneration = 0
    /// Reload results arriving while an inline rename is active are buffered so
    /// the edited row isn't torn out from under the field editor.
    private var pendingEntries: [Entry]?
    /// Entry that should enter rename mode as soon as it appears after a reload
    /// (used by New Folder, which renames immediately, Finder-style).
    private var pendingRenameURL: URL?
    /// Pasteboard changeCount at the time of the last ⌘X; a matching count at
    /// paste time means "our cut is still current" and turns the paste into a
    /// move. Other apps (Finder) ignore the marker and copy, as they should.
    private var cutPendingChangeCount: Int?

    private enum SelectionIntent {
        case preserve
        case reset
        case select(Set<URL>)
    }
    private var pendingSelectionIntent: SelectionIntent = .reset

    init(root: URL, settings: SettingsStore = .shared, favoritesStore: FavoritesStore? = nil) {
        self.currentURL = root
        self.settings = settings
        self.favoritesStore = favoritesStore ?? .shared
        self.sortField = settings.sortField
        self.sortAscending = settings.sortAscending
        self.showHiddenFiles = settings.showHiddenFiles
        startWatching(root)
        reloadDirectory(selecting: .reset)
    }

    // MARK: - Derived state

    var filteredEntries: [Entry] {
        guard !query.isEmpty else { return entries }
        return entries
            .compactMap { entry -> (Entry, Int)? in
                guard let score = FuzzyMatcher.score(entry.name, query: query) else { return nil }
                return (entry, score)
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1
                    ? lhs.1 > rhs.1
                    : lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }

    var selectedEntries: [Entry] {
        filteredEntries.filter { selectedURLs.contains($0.url) }
    }

    var leadEntry: Entry? {
        guard let lead = leadSelectionURL else { return nil }
        return filteredEntries.first { $0.url == lead }
    }

    var previewURL: URL? { leadSelectionURL }

    var hasSelection: Bool { !selectedEntries.isEmpty }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    var pasteboardHasFileURLs: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: Self.readingOptions)
    }

    private var actionTargets: [URL] { selectedEntries.map(\.url) }

    // MARK: - Selection

    func setSelection(_ urls: Set<URL>, lead: URL?) {
        selectedURLs = urls
        leadSelectionURL = lead ?? urls.first
        selectionAnchorURL = leadSelectionURL
    }

    func select(_ entry: Entry) {
        setSelection([entry.url], lead: entry.url)
    }

    func selectAll() {
        let list = filteredEntries
        guard !list.isEmpty else { return }
        selectedURLs = Set(list.map(\.url))
        if leadSelectionURL == nil { leadSelectionURL = list.first?.url }
    }

    func moveSelection(by delta: Int, extending: Bool = false) {
        let list = filteredEntries
        guard !list.isEmpty else { return }
        guard let leadIndex = leadSelectionURL.flatMap({ url in list.firstIndex { $0.url == url } }) else {
            let index = delta >= 0 ? 0 : list.count - 1
            setSelection([list[index].url], lead: list[index].url)
            return
        }
        let newIndex = min(max(leadIndex + delta, 0), list.count - 1)
        let newLead = list[newIndex].url
        if extending {
            let anchorIndex = selectionAnchorURL.flatMap({ url in list.firstIndex { $0.url == url } }) ?? leadIndex
            selectionAnchorURL = list[anchorIndex].url
            let range = min(anchorIndex, newIndex)...max(anchorIndex, newIndex)
            selectedURLs = Set(list[range].map(\.url))
            leadSelectionURL = newLead
        } else {
            setSelection([newLead], lead: newLead)
        }
    }

    private func resetSelectionToFirstMatch() {
        if let first = filteredEntries.first {
            setSelection([first.url], lead: first.url)
        } else {
            setSelection([], lead: nil)
        }
    }

    // MARK: - Directory loading

    func reloadDirectory() {
        reloadDirectory(selecting: .preserve)
    }

    private func reloadDirectory(selecting intent: SelectionIntent) {
        pendingSelectionIntent = intent
        loadGeneration += 1
        let generation = loadGeneration
        let url = currentURL
        let includeHidden = showHiddenFiles
        let field = sortField
        let ascending = sortAscending
        Task.detached(priority: .userInitiated) { [weak self] in
            let loaded = FileBrowserModel.loadEntries(
                at: url, includeHidden: includeHidden, field: field, ascending: ascending
            )
            await MainActor.run { [weak self] in
                self?.finishLoad(loaded, generation: generation, url: url)
            }
        }
    }

    private nonisolated static func loadEntries(
        at url: URL, includeHidden: Bool, field: SortField, ascending: Bool
    ) -> [Entry] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey
        ]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let contents = (try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: options
        )) ?? []
        let mapped = contents.map { url -> Entry in
            let values = try? url.resourceValues(forKeys: keys)
            return Entry(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                isHidden: values?.isHidden ?? false,
                modificationDate: values?.contentModificationDate,
                fileSize: (values?.fileSize).map(Int64.init)
            )
        }
        return EntrySorting.sorted(mapped, by: field, ascending: ascending)
    }

    private func finishLoad(_ loaded: [Entry], generation: Int, url: URL) {
        guard generation == loadGeneration, url == currentURL else { return }
        if renamingURL != nil {
            pendingEntries = loaded
            return
        }
        applyEntries(loaded)
    }

    private func applyEntries(_ newEntries: [Entry]) {
        entries = newEntries
        switch pendingSelectionIntent {
        case .reset:
            resetSelectionToFirstMatch()
        case .select(let urls):
            let wanted = Set(urls.map(\.standardizedFileURL))
            let matched = filteredEntries.filter { wanted.contains($0.url.standardizedFileURL) }
            if matched.isEmpty {
                resetSelectionToFirstMatch()
            } else {
                selectedURLs = Set(matched.map(\.url))
                leadSelectionURL = matched.first?.url
                selectionAnchorURL = leadSelectionURL
            }
        case .preserve:
            let existing = Set(entries.map(\.url))
            selectedURLs = selectedURLs.filter { existing.contains($0) }
            if let lead = leadSelectionURL, !existing.contains(lead) {
                leadSelectionURL = selectedURLs.first
                selectionAnchorURL = leadSelectionURL
            }
        }
        pendingSelectionIntent = .preserve
        if let target = pendingRenameURL {
            pendingRenameURL = nil
            if entries.contains(where: { $0.url == target }) {
                renamingURL = target
            }
        }
    }

    private func flushPendingEntries() {
        if let pending = pendingEntries {
            pendingEntries = nil
            applyEntries(pending)
        }
    }

    // MARK: - Sorting & hidden files

    func setSort(field: SortField, ascending: Bool) {
        sortField = field
        sortAscending = ascending
        settings.sortField = field
        settings.sortAscending = ascending
        entries = EntrySorting.sorted(entries, by: field, ascending: ascending)
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        settings.showHiddenFiles = showHiddenFiles
        reloadDirectory(selecting: .preserve)
    }

    // MARK: - Navigation

    /// Enter: descend into a single selected directory, or open the selection.
    func activateSelection() {
        let selection = selectedEntries
        guard !selection.isEmpty else { NSSound.beep(); return }
        if selection.count == 1, let entry = selection.first, entry.isDirectory {
            navigate(to: entry.url)
            return
        }
        for entry in selection {
            NSWorkspace.shared.open(entry.url)
        }
    }

    /// Backspace: delete a query character, or go to the parent directory when
    /// the query is empty.
    func backspace() {
        if !query.isEmpty {
            query.removeLast()
        } else {
            goToParent()
        }
    }

    func goToParent() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        let previous = currentURL
        pushHistory()
        performNavigation(to: parent, selecting: .select([previous]))
    }

    func navigate(to url: URL) {
        guard url.standardizedFileURL != currentURL.standardizedFileURL else {
            reloadDirectory()
            return
        }
        pushHistory()
        performNavigation(to: url, selecting: .reset)
    }

    func goBack() {
        guard let location = history.goBack(from: currentLocation) else { NSSound.beep(); return }
        performNavigation(
            to: location.url,
            selecting: location.selectedURLs.isEmpty ? .reset : .select(location.selectedURLs)
        )
    }

    func goForward() {
        guard let location = history.goForward(from: currentLocation) else { NSSound.beep(); return }
        performNavigation(
            to: location.url,
            selecting: location.selectedURLs.isEmpty ? .reset : .select(location.selectedURLs)
        )
    }

    func jumpToFavorite(_ index: Int) {
        let favorites = favoritesStore.favorites
        guard favorites.indices.contains(index) else { return }
        navigate(to: favorites[index].url)
    }

    /// ⇧⌘H goes to the real home directory — favorites are editable, so
    /// "first favorite" is no longer a stable stand-in.
    func goHome() {
        navigate(to: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Adds the lead selection (a directory) to the shared favorites.
    func addLeadToFavorites() {
        guard let entry = leadEntry, entry.isDirectory else { NSSound.beep(); return }
        favoritesStore.add(entry.url)
        statusMessage = "Added \(entry.name) to Favorites"
    }

    var canAddLeadToFavorites: Bool {
        guard let entry = leadEntry, entry.isDirectory else { return false }
        return !favoritesStore.contains(entry.url)
    }

    private var currentLocation: NavigationHistory.Location {
        NavigationHistory.Location(url: currentURL, selectedURLs: selectedURLs)
    }

    private func pushHistory() {
        history.recordNavigation(from: currentLocation)
    }

    private func performNavigation(to url: URL, selecting intent: SelectionIntent) {
        currentURL = url
        query = ""
        startWatching(url)
        reloadDirectory(selecting: intent)
    }

    /// Called when the owning window closes: release file descriptors and
    /// stop publishing.
    func teardown() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Live watching

    private func startWatching(_ url: URL) {
        watcher?.stop()
        watcher = DirectoryWatcher(url: url) { [weak self] event in
            guard let self else { return }
            switch event {
            case .contentsChanged:
                self.reloadDirectory()
            case .directoryGone:
                self.navigateToNearestExistingAncestor()
            }
        }
    }

    /// The watched directory itself disappeared; fall back to the closest
    /// ancestor that still exists. The vanished location is not pushed onto the
    /// history stack — going "back" to it would fail.
    private func navigateToNearestExistingAncestor() {
        var candidate = currentURL.deletingLastPathComponent()
        let fm = FileManager.default
        while candidate.path != "/", !fm.fileExists(atPath: candidate.path) {
            candidate = candidate.deletingLastPathComponent()
        }
        performNavigation(to: candidate, selecting: .reset)
    }

    // MARK: - Query

    func appendToQuery(_ string: String) { query.append(string) }

    func clearQuery() { query = "" }

    // MARK: - Simple actions

    func revealSelection() {
        guard !actionTargets.isEmpty else { NSSound.beep(); return }
        FileActionsService.reveal(actionTargets)
    }

    func quickLookSelection() {
        guard !actionTargets.isEmpty else { NSSound.beep(); return }
        QuickLookController.shared.preview(actionTargets)
    }

    // MARK: - Trash

    func trashSelection() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        performTrash(targets)
    }

    private func performTrash(_ urls: [URL]) {
        let result = FileActionsService.moveToTrash(urls)
        let restorable = result.succeededPairs.compactMap { pair in
            pair.to.map { trashURL in (from: trashURL, to: pair.from) }
        }
        if !restorable.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                model.performURLMoves(restorable, actionName: "Move to Trash")
            }
            undoManager.setActionName("Move to Trash")
        }
        statusMessage = "Trashed \(result.summary)"
        reloadDirectory(selecting: .preserve)
    }

    /// Moves each `from` to `to` and registers the reverse moves as the
    /// undo/redo counterpart. Shared primitive for trash-restore and move-undo.
    private func performURLMoves(_ pairs: [(from: URL, to: URL)], actionName: String) {
        let fm = FileManager.default
        var done: [(from: URL, to: URL)] = []
        for pair in pairs {
            do {
                try fm.moveItem(at: pair.from, to: pair.to)
                done.append(pair)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        if !done.isEmpty {
            let inverse = done.map { (from: $0.to, to: $0.from) }
            undoManager.registerUndo(withTarget: self) { model in
                model.performURLMoves(inverse, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        reloadDirectory(selecting: .select(Set(done.map(\.to))))
    }

    /// Undo helper for operations that created items (New Folder, Duplicate,
    /// Paste-Copy): trashing the created items, with restore as the redo.
    private func trashCreatedItems(_ urls: [URL], actionName: String) {
        let result = FileActionsService.moveToTrash(urls)
        let restorable = result.succeededPairs.compactMap { pair in
            pair.to.map { trashURL in (from: trashURL, to: pair.from) }
        }
        if !restorable.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                model.performURLMoves(restorable, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        reloadDirectory(selecting: .preserve)
    }

    // MARK: - Rename

    func beginRename() {
        guard let entry = leadEntry else { NSSound.beep(); return }
        renamingURL = entry.url
    }

    func cancelRename() {
        renamingURL = nil
        flushPendingEntries()
    }

    /// Returns false when the rename failed and the field editor should stay
    /// open for correction.
    func commitRename(to newName: String) -> Bool {
        guard let url = renamingURL else { return true }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != url.lastPathComponent else {
            cancelRename()
            return true
        }
        switch FileActionsService.rename(url, to: name) {
        case .success(let newURL):
            renamingURL = nil
            pendingEntries = nil
            registerRenameUndo(from: newURL, backTo: url.lastPathComponent)
            undoManager.setActionName("Rename")
            reloadDirectory(selecting: .select([newURL]))
            return true
        case .failure(let error):
            NSSound.beep()
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func registerRenameUndo(from url: URL, backTo previousName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            model.performRename(url, to: previousName)
        }
    }

    private func performRename(_ url: URL, to newName: String) {
        switch FileActionsService.rename(url, to: newName) {
        case .success(let newURL):
            registerRenameUndo(from: newURL, backTo: url.lastPathComponent)
            undoManager.setActionName("Rename")
            reloadDirectory(selecting: .select([newURL]))
        case .failure(let error):
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - New folder & duplicate

    func createNewFolder() {
        switch FileActionsService.createFolder(in: currentURL) {
        case .success(let url):
            undoManager.registerUndo(withTarget: self) { model in
                model.trashCreatedItems([url], actionName: "New Folder")
            }
            undoManager.setActionName("New Folder")
            query = ""
            pendingRenameURL = url
            reloadDirectory(selecting: .select([url]))
        case .failure(let error):
            NSSound.beep()
            statusMessage = error.localizedDescription
        }
    }

    func duplicateSelection() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        let result = FileActionsService.duplicate(targets)
        let created = result.succeededPairs.compactMap(\.to)
        if !created.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                model.trashCreatedItems(created, actionName: "Duplicate")
            }
            undoManager.setActionName("Duplicate")
        }
        statusMessage = "Duplicated \(result.summary)"
        reloadDirectory(selecting: .select(Set(created)))
    }

    // MARK: - Clipboard (system pasteboard)

    func copySelection() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        writeToPasteboard(targets)
        clearCutMark()
        statusMessage = "Copied \(targets.count) item(s)"
    }

    func cutSelection() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        writeToPasteboard(targets)
        cutPendingChangeCount = NSPasteboard.general.changeCount
        cutPendingURLs = Set(targets.map(\.standardizedFileURL))
        statusMessage = "Cut \(targets.count) item(s)"
    }

    func paste() {
        let urls = readPasteboardFileURLs()
        guard !urls.isEmpty else { NSSound.beep(); return }
        let isPendingCut = cutPendingChangeCount == NSPasteboard.general.changeCount
        // Either way the cut marker is spent: a foreign pasteboard write (other
        // app copied something) must also stop dimming the previously cut rows.
        clearCutMark()
        if isPendingCut {
            performMove(urls, to: currentURL)
        } else {
            performCopy(urls, to: currentURL)
        }
    }

    /// ⌥⌘V, Finder's "Move Item Here": moves the pasteboard items regardless of
    /// whether they were put there by ⌘C or ⌘X — including by other apps.
    func moveItemHere() {
        let urls = readPasteboardFileURLs()
        guard !urls.isEmpty else { NSSound.beep(); return }
        clearCutMark()
        performMove(urls, to: currentURL)
    }

    private static let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    private func writeToPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func readPasteboardFileURLs() -> [URL] {
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self], options: Self.readingOptions
        )
        return (objects as? [URL]) ?? []
    }

    private func clearCutMark() {
        cutPendingChangeCount = nil
        cutPendingURLs = []
    }

    // MARK: - Copy/move engines (paste & drop)

    private func performCopy(_ urls: [URL], to directory: URL) {
        let result = FileActionsService.copy(urls, to: directory)
        let created = result.succeededPairs.compactMap(\.to)
        if !created.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                model.trashCreatedItems(created, actionName: "Copy")
            }
            undoManager.setActionName("Copy")
        }
        statusMessage = "Pasted \(result.summary)"
        finishTransfer(into: directory, produced: created)
    }

    private func performMove(_ urls: [URL], to directory: URL) {
        // Skip no-op moves; the service would otherwise " copy"-rename in place.
        let movable = urls.filter {
            $0.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL
        }
        guard !movable.isEmpty else { return }
        let result = FileActionsService.move(movable, to: directory)
        let moved = result.succeededPairs.compactMap(\.to)
        let inverse = result.succeededPairs.compactMap { pair in
            pair.to.map { destination in (from: destination, to: pair.from) }
        }
        if !inverse.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                model.performURLMoves(inverse, actionName: "Move")
            }
            undoManager.setActionName("Move")
        }
        statusMessage = "Moved \(result.summary)"
        finishTransfer(into: directory, produced: moved)
    }

    private func finishTransfer(into directory: URL, produced: [URL]) {
        if directory.standardizedFileURL == currentURL.standardizedFileURL, !produced.isEmpty {
            reloadDirectory(selecting: .select(Set(produced)))
        } else {
            reloadDirectory(selecting: .preserve)
        }
    }

    // MARK: - Drag & drop

    /// Returns true when the drop was accepted and performed.
    @discardableResult
    func handleDrop(of urls: [URL], into destination: URL, copy: Bool) -> Bool {
        let targets = validDropTargets(urls, destination: destination, copying: copy)
        guard !targets.isEmpty else { return false }
        if copy {
            performCopy(targets, to: destination)
        } else {
            performMove(targets, to: destination)
        }
        return true
    }

    /// Filters out drops that would be no-ops or cycles (an item onto itself,
    /// a folder into its own subtree, a move into its current parent).
    func validDropTargets(_ urls: [URL], destination: URL, copying: Bool) -> [URL] {
        let destinationURL = destination.standardizedFileURL
        return urls.filter { url in
            let source = url.standardizedFileURL
            if source == destinationURL { return false }
            if destinationURL.path.hasPrefix(source.path + "/") { return false }
            if !copying, source.deletingLastPathComponent() == destinationURL { return false }
            return true
        }
    }
}
