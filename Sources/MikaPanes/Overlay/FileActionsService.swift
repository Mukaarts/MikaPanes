import AppKit

/// Keyboard-triggered file operations used by the overlay. Works on a list of
/// URLs regardless of whether they came from the own browser or the Finder.
enum FileActionsService {

    struct BatchResult {
        var succeeded: Int = 0
        var failures: [(url: URL, error: Error)] = []

        var summary: String {
            if failures.isEmpty { return "\(succeeded) item(s)" }
            return "\(succeeded) ok, \(failures.count) failed"
        }
    }

    /// Reveal items in Finder, selecting them.
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Move items to the Trash.
    @discardableResult
    static func moveToTrash(_ urls: [URL]) -> BatchResult {
        var result = BatchResult()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.succeeded += 1
            } catch {
                result.failures.append((url, error))
            }
        }
        return result
    }

    /// Copy items into a destination directory.
    @discardableResult
    static func copy(_ urls: [URL], to directory: URL) -> BatchResult {
        transfer(urls, to: directory, move: false)
    }

    /// Move items into a destination directory. `FileManager.moveItem` already
    /// performs copy-then-delete across volumes.
    @discardableResult
    static func move(_ urls: [URL], to directory: URL) -> BatchResult {
        transfer(urls, to: directory, move: true)
    }

    private static func transfer(_ urls: [URL], to directory: URL, move: Bool) -> BatchResult {
        var result = BatchResult()
        let fm = FileManager.default
        for url in urls {
            let destination = uniqueDestination(for: url, in: directory)
            // Skip no-op transfers into the item's own directory.
            if url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
               !move {
                continue
            }
            do {
                if move {
                    try fm.moveItem(at: url, to: destination)
                } else {
                    try fm.copyItem(at: url, to: destination)
                }
                result.succeeded += 1
            } catch {
                result.failures.append((url, error))
            }
        }
        return result
    }

    /// Avoid clobbering: append " copy", " copy 2", … if the destination exists.
    private static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            counter += 1
            let suffix = counter == 2 ? " copy" : " copy \(counter - 1)"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
        }
        return candidate
    }
}
