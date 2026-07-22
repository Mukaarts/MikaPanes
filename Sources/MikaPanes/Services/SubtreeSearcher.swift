import Foundation

/// Where a non-empty query looks for matches.
enum SearchScope: CaseIterable, Hashable {
    case folder, subtree, spotlight

    var label: String {
        switch self {
        case .folder: return "This Folder"
        case .subtree: return "Subfolders"
        case .spotlight: return "Mac"
        }
    }

    var next: SearchScope {
        switch self {
        case .folder: return .subtree
        case .subtree: return .spotlight
        case .spotlight: return .folder
        }
    }
}

enum SearchStatus: Equatable {
    case idle
    case searching
    case done(Int)
    case capped(Int)
}

/// A search match with its fuzzy score, so streamed batches can be rank-merged.
struct SearchHit {
    let entry: FileBrowserModel.Entry
    let score: Int
}

/// Recursive filename search below a root folder. Runs off the main actor,
/// streams scored batches to a MainActor callback, caps the result count and
/// honours cancellation of the surrounding task.
enum SubtreeSearcher {

    static let resultCap = 500

    /// Batches are incremental (hits since the previous callback); the last
    /// callback carries `finished == true`. A cancelled task stops silently.
    nonisolated static func search(
        root: URL,
        query: String,
        includeHidden: Bool,
        cap: Int = resultCap,
        onBatch: @escaping @MainActor (_ hits: [SearchHit], _ finished: Bool, _ capped: Bool) -> Void
    ) async {
        if Task.isCancelled { return }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            await onBatch([], true, false)
            return
        }

        var pending: [SearchHit] = []
        var total = 0
        var scanned = 0
        // DirectoryEnumerator's Sequence iteration is unavailable in async
        // contexts; step it manually.
        while let object = enumerator.nextObject() {
            guard let url = object as? URL else { continue }
            scanned += 1
            if scanned % 64 == 0 {
                if Task.isCancelled { return }
                if !pending.isEmpty {
                    let batch = pending
                    pending = []
                    await onBatch(batch, false, false)
                }
            }
            guard let score = FuzzyMatcher.score(url.lastPathComponent, query: query) else { continue }
            pending.append(SearchHit(entry: FileBrowserModel.makeEntry(for: url), score: score))
            total += 1
            if total >= cap {
                await onBatch(pending, true, true)
                return
            }
        }
        if Task.isCancelled { return }
        await onBatch(pending, true, false)
    }

    /// Rank-merge: score descending, name ascending as the tie-break.
    static func merge(_ existing: [SearchHit], adding: [SearchHit]) -> [SearchHit] {
        (existing + adding).sorted { lhs, rhs in
            lhs.score != rhs.score
                ? lhs.score > rhs.score
                : lhs.entry.name.localizedCaseInsensitiveCompare(rhs.entry.name) == .orderedAscending
        }
    }
}
