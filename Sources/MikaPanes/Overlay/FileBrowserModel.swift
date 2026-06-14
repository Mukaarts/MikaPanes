import AppKit
import SwiftUI

/// Backing state for the browser window: directory contents, fuzzy filter,
/// selection, an internal clipboard for copy/cut/paste, and the file actions
/// triggered from the keyboard.
@MainActor
final class FileBrowserModel: ObservableObject {

    struct Entry: Identifiable, Hashable {
        let url: URL
        let name: String
        let isDirectory: Bool
        var id: URL { url }
    }

    struct Favorite: Identifiable, Hashable {
        let name: String
        let systemImage: String
        let url: URL
        var id: URL { url }
    }

    private enum ClipboardMode { case copy, cut }

    @Published var currentURL: URL
    @Published private(set) var entries: [Entry] = []
    @Published var query: String = "" { didSet { selectionIndex = 0 } }
    @Published var selectionIndex: Int = 0
    @Published var statusMessage: String?

    let favorites: [Favorite]
    private var clipboard: (urls: [URL], mode: ClipboardMode)?

    init(root: URL) {
        self.currentURL = root
        self.favorites = Self.defaultFavorites(root: root)
        reloadDirectory()
    }

    private static func defaultFavorites(root: URL) -> [Favorite] {
        let fm = FileManager.default
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? {
            fm.urls(for: d, in: .userDomainMask).first
        }
        var favorites: [Favorite] = [
            Favorite(name: "Home", systemImage: "house", url: fm.homeDirectoryForCurrentUser)
        ]
        if let url = dir(.desktopDirectory) {
            favorites.append(Favorite(name: "Desktop", systemImage: "menubar.dock.rectangle", url: url))
        }
        if let url = dir(.documentDirectory) {
            favorites.append(Favorite(name: "Documents", systemImage: "doc", url: url))
        }
        if let url = dir(.downloadsDirectory) {
            favorites.append(Favorite(name: "Downloads", systemImage: "arrow.down.circle", url: url))
        }
        if !favorites.contains(where: { $0.url.standardizedFileURL == root.standardizedFileURL }) {
            favorites.append(Favorite(name: root.lastPathComponent, systemImage: "star", url: root))
        }
        return favorites
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

    var selectedEntry: Entry? {
        let list = filteredEntries
        guard list.indices.contains(selectionIndex) else { return nil }
        return list[selectionIndex]
    }

    var previewURL: URL? { selectedEntry?.url }

    private var actionTargets: [URL] { selectedEntry.map { [$0.url] } ?? [] }

    // MARK: - Directory loading

    func reloadDirectory() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        entries = contents
            .map { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return Entry(url: url, name: url.lastPathComponent, isDirectory: isDir)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        selectionIndex = 0
    }

    // MARK: - Navigation

    func moveSelection(by delta: Int) {
        let count = filteredEntries.count
        guard count > 0 else { return }
        selectionIndex = (selectionIndex + delta + count) % count
    }

    /// Enter: descend into a directory (clearing the query) or open a file.
    func activateSelection() {
        guard let entry = selectedEntry else { return }
        if entry.isDirectory {
            navigate(to: entry.url)
        } else {
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
        navigate(to: parent)
        if let index = filteredEntries.firstIndex(where: {
            $0.url.standardizedFileURL == previous.standardizedFileURL
        }) {
            selectionIndex = index
        }
    }

    func navigate(to url: URL) {
        currentURL = url
        query = ""
        reloadDirectory()
    }

    func jumpToFavorite(_ index: Int) {
        guard favorites.indices.contains(index) else { return }
        navigate(to: favorites[index].url)
    }

    func select(_ entry: Entry) {
        if let index = filteredEntries.firstIndex(of: entry) {
            selectionIndex = index
        }
    }

    func appendToQuery(_ string: String) { query.append(string) }

    func clearQuery() { query = "" }

    // MARK: - Actions

    func revealSelection() {
        guard !actionTargets.isEmpty else { NSSound.beep(); return }
        FileActionsService.reveal(actionTargets)
    }

    func quickLookSelection() {
        guard !actionTargets.isEmpty else { NSSound.beep(); return }
        QuickLookController.shared.preview(actionTargets)
    }

    func trashSelection() {
        guard !actionTargets.isEmpty else { NSSound.beep(); return }
        let result = FileActionsService.moveToTrash(actionTargets)
        statusMessage = "Trashed \(result.summary)"
        reloadDirectory()
    }

    func copySelection() {
        guard let url = selectedEntry?.url else { NSSound.beep(); return }
        clipboard = ([url], .copy)
        statusMessage = "Copied \(url.lastPathComponent)"
    }

    func cutSelection() {
        guard let url = selectedEntry?.url else { NSSound.beep(); return }
        clipboard = ([url], .cut)
        statusMessage = "Cut \(url.lastPathComponent)"
    }

    func paste() {
        guard let clip = clipboard else { NSSound.beep(); return }
        let result: FileActionsService.BatchResult
        switch clip.mode {
        case .copy:
            result = FileActionsService.copy(clip.urls, to: currentURL)
            statusMessage = "Pasted \(result.summary)"
        case .cut:
            result = FileActionsService.move(clip.urls, to: currentURL)
            statusMessage = "Moved \(result.summary)"
            clipboard = nil
        }
        reloadDirectory()
    }
}
