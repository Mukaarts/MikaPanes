import Foundation

/// Watches a single directory (non-recursively) for content changes via a
/// dispatch file-system source. Events are debounced so bursts of file
/// operations collapse into one reload.
@MainActor
final class DirectoryWatcher {

    enum Event {
        case contentsChanged
        case directoryGone
    }

    private let source: DispatchSourceFileSystemObject
    private var debounce: DispatchWorkItem?

    init?(url: URL, handler: @escaping (Event) -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .link],
            queue: .main
        )
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source.data
            if flags.contains(.delete) || flags.contains(.rename),
               !FileManager.default.fileExists(atPath: url.path) {
                self.stop()
                handler(.directoryGone)
                return
            }
            self.debounce?.cancel()
            let work = DispatchWorkItem { handler(.contentsChanged) }
            self.debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        source.resume()
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        if !source.isCancelled { source.cancel() }
    }

    deinit {
        if !source.isCancelled { source.cancel() }
    }
}
