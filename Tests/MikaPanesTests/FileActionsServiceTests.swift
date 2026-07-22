import Foundation
import Testing
@testable import MikaPanes

@Suite struct FileActionsServiceTests {

    private let fm = FileManager.default

    /// Unique fixture directory per test; caller removes it via defer.
    private func makeTempDir() throws -> URL {
        let dir = fm.temporaryDirectory
            .appendingPathComponent("FileActionsServiceTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func makeFile(_ name: String, in dir: URL, contents: String = "hello") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - rename

    @Test func renameSucceeds() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let file = try makeFile("old.txt", in: dir)

        let result = FileActionsService.rename(file, to: "new.txt")
        let newURL = try result.get()

        #expect(newURL.lastPathComponent == "new.txt")
        #expect(newURL.deletingLastPathComponent().path == dir.path)
        #expect(fm.fileExists(atPath: newURL.path))
        #expect(!fm.fileExists(atPath: file.path))
    }

    @Test func renameToExistingOtherNameFails() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let a = try makeFile("a.txt", in: dir, contents: "aaa")
        try makeFile("b.txt", in: dir, contents: "bbb")

        let result = FileActionsService.rename(a, to: "b.txt")

        guard case .failure(let error) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(error is FileActionError)
        // Nothing moved or clobbered.
        #expect(try String(contentsOf: a, encoding: .utf8) == "aaa")
        #expect(try String(contentsOf: dir.appendingPathComponent("b.txt"), encoding: .utf8) == "bbb")
    }

    @Test func renameCaseOnlyChangesCasing() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let file = try makeFile("readme", in: dir)

        let result = FileActionsService.rename(file, to: "README")
        let newURL = try result.get()

        #expect(newURL.lastPathComponent == "README")
        // Verify the on-disk casing via the directory listing. On a
        // case-sensitive filesystem this is a plain move and still holds.
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains("README"))
        #expect(!names.contains("readme"))
    }

    // MARK: - createFolder

    @Test func createFolderUsesFinderNamingSequence() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }

        let first = try FileActionsService.createFolder(in: dir).get()
        let second = try FileActionsService.createFolder(in: dir).get()
        let third = try FileActionsService.createFolder(in: dir).get()

        #expect(first.lastPathComponent == "untitled folder")
        #expect(second.lastPathComponent == "untitled folder 2")
        #expect(third.lastPathComponent == "untitled folder 3")
        for url in [first, second, third] {
            var isDir: ObjCBool = false
            #expect(fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
        }
    }

    // MARK: - duplicate

    @Test func duplicateFileAppendsCopySuffixes() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let file = try makeFile("a.txt", in: dir, contents: "payload")

        let first = FileActionsService.duplicate([file])
        #expect(first.failures.isEmpty)
        #expect(first.succeededPairs.first?.to?.lastPathComponent == "a copy.txt")

        let second = FileActionsService.duplicate([file])
        #expect(second.failures.isEmpty)
        #expect(second.succeededPairs.first?.to?.lastPathComponent == "a copy 2.txt")

        let copyURL = try #require(first.succeededPairs.first?.to)
        #expect(try String(contentsOf: copyURL, encoding: .utf8) == "payload")
    }

    @Test func duplicateFolderWithDotInNameKeepsFullName() throws {
        // Regression: "v1.2" must not be split into base "v1" + extension "2".
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("v1.2")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try makeFile("inner.txt", in: folder, contents: "inner")

        let result = FileActionsService.duplicate([folder])

        #expect(result.failures.isEmpty)
        let copy = try #require(result.succeededPairs.first?.to)
        #expect(copy.lastPathComponent == "v1.2 copy")
        let innerCopy = copy.appendingPathComponent("inner.txt")
        #expect(try String(contentsOf: innerCopy, encoding: .utf8) == "inner")
    }

    // MARK: - copy / move

    @Test func copyIntoOwnDirectoryCreatesCopy() throws {
        // Regression: copies into the item's own directory used to be skipped.
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let file = try makeFile("a.txt", in: dir, contents: "payload")

        let result = FileActionsService.copy([file], to: dir)

        #expect(result.failures.isEmpty)
        #expect(result.succeeded == 1)
        #expect(result.summary == "1 item(s)")
        let copy = try #require(result.succeededPairs.first?.to)
        #expect(copy.lastPathComponent == "a copy.txt")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "payload")
        // Original untouched.
        #expect(fm.fileExists(atPath: file.path))
    }

    @Test func moveAcrossDirectoriesReportsPairs() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let source = dir.appendingPathComponent("src")
        let target = dir.appendingPathComponent("dst")
        try fm.createDirectory(at: source, withIntermediateDirectories: false)
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        let file = try makeFile("a.txt", in: source, contents: "payload")

        let result = FileActionsService.move([file], to: target)

        #expect(result.failures.isEmpty)
        let pair = try #require(result.succeededPairs.first)
        #expect(pair.from.path == file.path)
        #expect(pair.to?.path == target.appendingPathComponent("a.txt").path)
        #expect(!fm.fileExists(atPath: file.path))
        #expect(fm.fileExists(atPath: target.appendingPathComponent("a.txt").path))
    }

    // MARK: - moveToTrash

    @Test func moveToTrashReportsPairOrFailure() throws {
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let file = try makeFile("trash-me.txt", in: dir)

        let result = FileActionsService.moveToTrash([file])

        if result.failures.isEmpty {
            let pair = try #require(result.succeededPairs.first)
            #expect(pair.from == file)
            #expect(!fm.fileExists(atPath: file.path))
            // `to` may legitimately be nil; when present, clean up the item.
            if let trashed = pair.to {
                #expect(fm.fileExists(atPath: trashed.path))
                try? fm.removeItem(at: trashed)
            }
        } else {
            // Trashing can fail on volumes without a Trash (e.g. CI sandboxes).
            #expect(result.succeededPairs.isEmpty)
            #expect(result.failures.first?.url == file)
        }
    }
}
