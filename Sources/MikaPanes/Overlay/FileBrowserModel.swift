import AppKit
import SwiftUI

/// Which item(s) overlay actions operate on.
enum OverlaySourceMode: String {
    case ownBrowser
    case finderSelection

    var label: String {
        switch self {
        case .ownBrowser: return "Browser"
        case .finderSelection: return "Finder selection"
        }
    }
}

/// Backing state for the overlay: directory contents, fuzzy filter, selection,
/// and the file actions triggered from the keyboard.
@MainActor
final class FileBrowserModel: ObservableObject {

    struct Entry: Identifiable, Hashable {
        let url: URL
        let name: String
        let isDirectory: Bool
        var id: URL { url }
    }

    @Published var currentURL: URL
    @Published private(set) var entries: [Entry] = []
    @Published var query: String = "" { didSet { selectionIndex = 0 } }
    @Published var selectionIndex: Int = 0
    @Published var sourceMode: OverlaySourceMode = .ownBrowser
    @Published private(set) var finderSelection: [URL] = []
    @Published var statusMessage: String?

    init(root: URL) {
        self.currentURL = root
        reloadDirectory()
    }

    // MARK: - Derived state

    /// Entries filtered by the fuzzy query and ranked by score (directories first
    /// when scores tie).
    var filteredEntries: [Entry] {
        guard !query.isEmpty else { return entries }
        return entries
            .compactMap { entry -> (Entry, Int)? in
                guard let score = FuzzyMatcher.score(entry.name, query: query) else { return nil }
                return (entry, score)
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }

    var selectedEntry: Entry? {
        let list = filteredEntries
        guard list.indices.contains(selectionIndex) else { return nil }
        return list[selectionIndex]
    }

    /// URLs that actions apply to, depending on the source mode.
    var actionTargets: [URL] {
        switch sourceMode {
        case .ownBrowser:
            return selectedEntry.map { [$0.url] } ?? []
        case .finderSelection:
            return finderSelection
        }
    }

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

    func refreshFinderSelection() {
        finderSelection = FinderSelectionService.currentSelection()
        if finderSelection.isEmpty {
            statusMessage = "No Finder selection"
        } else {
            statusMessage = "\(finderSelection.count) item(s) from Finder"
        }
    }

    // MARK: - Navigation

    func moveSelection(by delta: Int) {
        let count = filteredEntries.count
        guard count > 0 else { return }
        selectionIndex = (selectionIndex + delta + count) % count
    }

    /// Enter: descend into a directory (clearing the query) or open a file.
    /// Returns `true` if the overlay should close (a file was opened).
    func activateSelection() -> Bool {
        guard let entry = selectedEntry else { return false }
        if entry.isDirectory {
            currentURL = entry.url
            query = ""
            reloadDirectory()
            return false
        } else {
            NSWorkspace.shared.open(entry.url)
            return true
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
        currentURL = parent
        query = ""
        reloadDirectory()
        // Highlight the directory we came from.
        if let index = filteredEntries.firstIndex(where: { $0.url.standardizedFileURL == previous.standardizedFileURL }) {
            selectionIndex = index
        }
    }

    func appendToQuery(_ string: String) {
        query.append(string)
    }

    func toggleSourceMode() {
        sourceMode = sourceMode == .ownBrowser ? .finderSelection : .ownBrowser
        if sourceMode == .finderSelection {
            refreshFinderSelection()
        } else {
            statusMessage = nil
        }
    }

    // MARK: - Actions

    func revealTargets() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        FileActionsService.reveal(targets)
    }

    func trashTargets() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        let result = FileActionsService.moveToTrash(targets)
        statusMessage = "Trashed \(result.summary)"
        if sourceMode == .ownBrowser { reloadDirectory() }
        else { refreshFinderSelection() }
    }

    func quickLookTargets() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        QuickLookController.shared.preview(targets)
    }

    /// Copy/Move the source items into the directory currently shown in the browser.
    func copyTargetsHere() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        let result = FileActionsService.copy(targets, to: currentURL)
        statusMessage = "Copied \(result.summary)"
        reloadDirectory()
    }

    func moveTargetsHere() {
        let targets = actionTargets
        guard !targets.isEmpty else { NSSound.beep(); return }
        let result = FileActionsService.move(targets, to: currentURL)
        statusMessage = "Moved \(result.summary)"
        reloadDirectory()
        if sourceMode == .finderSelection { refreshFinderSelection() }
    }
}
