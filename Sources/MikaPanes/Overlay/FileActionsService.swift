import AppKit

/// Errors produced by single-item file actions.
enum FileActionError: LocalizedError {
    case nameAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .nameAlreadyExists(let name):
            return "An item named \u{201C}\(name)\u{201D} already exists."
        }
    }
}

/// Keyboard-triggered file operations used by the overlay. Works on a list of
/// URLs regardless of whether they came from the own browser or the Finder.
enum FileActionsService {

    struct BatchResult {
        /// One entry per successful item; `to` is nil when the system did not
        /// report a resulting URL (e.g. some trash implementations).
        var succeededPairs: [(from: URL, to: URL?)] = []
        var failures: [(url: URL, error: Error)] = []

        var succeeded: Int { succeededPairs.count }

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
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                result.succeededPairs.append((from: url, to: trashedURL as URL?))
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

    /// Copy each item into its own directory, Finder-style (" copy", " copy 2").
    @discardableResult
    static func duplicate(_ urls: [URL]) -> BatchResult {
        var result = BatchResult()
        let fm = FileManager.default
        for url in urls {
            let destination = uniqueDestination(for: url, in: url.deletingLastPathComponent())
            do {
                try fm.copyItem(at: url, to: destination)
                result.succeededPairs.append((from: url, to: destination))
            } catch {
                result.failures.append((url, error))
            }
        }
        return result
    }

    /// Rename an item within its directory. Case-only renames ("readme" →
    /// "README") work on case-insensitive volumes via a temp-name detour.
    static func rename(_ url: URL, to newName: String) -> Result<URL, Error> {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        let destination = directory.appendingPathComponent(newName)

        if url.lastPathComponent == newName { return .success(url) }

        // On case-insensitive filesystems the destination "exists" during a
        // case-only rename — that is still the item itself, not a conflict.
        let renamingSameItem = isSameItem(url, destination)
        if fm.fileExists(atPath: destination.path), !renamingSameItem {
            return .failure(FileActionError.nameAlreadyExists(newName))
        }
        do {
            try fm.moveItem(at: url, to: destination)
            return .success(destination)
        } catch {
            guard renamingSameItem else { return .failure(error) }
            // Case-only rename rejected by the filesystem: go through a
            // temporary name in the same directory.
            let temp = directory.appendingPathComponent(".rename-\(UUID().uuidString)")
            do {
                try fm.moveItem(at: url, to: temp)
                try fm.moveItem(at: temp, to: destination)
                return .success(destination)
            } catch {
                return .failure(error)
            }
        }
    }

    /// Create "untitled folder" (or "untitled folder 2", …) in a directory.
    static func createFolder(in directory: URL) -> Result<URL, Error> {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("untitled folder")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = directory.appendingPathComponent("untitled folder \(counter)")
        }
        do {
            try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
            return .success(candidate)
        } catch {
            return .failure(error)
        }
    }

    private static func transfer(_ urls: [URL], to directory: URL, move: Bool) -> BatchResult {
        var result = BatchResult()
        let fm = FileManager.default
        for url in urls {
            let destination = uniqueDestination(for: url, in: directory)
            do {
                if move {
                    try fm.moveItem(at: url, to: destination)
                } else {
                    try fm.copyItem(at: url, to: destination)
                }
                result.succeededPairs.append((from: url, to: destination))
            } catch {
                result.failures.append((url, error))
            }
        }
        return result
    }

    /// Avoid clobbering: append " copy", " copy 2", … if the destination exists.
    private static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        // Directories have no extension to split off — a folder "v1.2" must
        // become "v1.2 copy", not "v1 copy.2". `hasDirectoryPath` is unreliable
        // for URLs built without a trailing slash, so ask the filesystem.
        var isDir: ObjCBool = false
        let treatAsDirectory = fm.fileExists(atPath: source.path, isDirectory: &isDir) && isDir.boolValue
        let ext = treatAsDirectory ? "" : source.pathExtension
        let base = treatAsDirectory
            ? source.lastPathComponent
            : source.deletingPathExtension().lastPathComponent
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

    /// True when both URLs point at the same filesystem item (handles
    /// case-insensitive volumes where the paths differ only in case).
    private static func isSameItem(_ a: URL, _ b: URL) -> Bool {
        guard
            let idA = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
            let idB = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else { return false }
        return idA.isEqual(idB)
    }
}
