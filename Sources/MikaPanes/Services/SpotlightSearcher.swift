import Foundation

/// Whole-Mac filename search backed by NSMetadataQuery (Spotlight). Lives and
/// reports strictly on the main actor; results update live while the query
/// keeps running.
@MainActor
final class SpotlightSearcher {

    static let resultCap = 500

    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private let onResults: (_ entries: [FileBrowserModel.Entry], _ finished: Bool, _ capped: Bool) -> Void

    init(
        searchString: String,
        onResults: @escaping (_ entries: [FileBrowserModel.Entry], _ finished: Bool, _ capped: Bool) -> Void
    ) {
        self.onResults = onResults
        query.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", searchString)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.operationQueue = .main

        let center = NotificationCenter.default
        // queue: .main makes the hop safe to assume.
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.collect() }
        })
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.collect() }
        })
        query.start()
    }

    private func collect() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let capped = query.resultCount > Self.resultCap
        let count = min(query.resultCount, Self.resultCap)
        var entries: [FileBrowserModel.Entry] = []
        entries.reserveCapacity(count)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            entries.append(FileBrowserModel.makeEntry(for: URL(fileURLWithPath: path)))
        }
        onResults(entries, true, capped)
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver(_:))
        observers = []
    }
}
