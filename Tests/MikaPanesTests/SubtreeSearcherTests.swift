import Foundation
import Testing
@testable import MikaPanes

@MainActor
@Suite struct SubtreeSearcherTests {

    private final class Collector {
        var hits: [SearchHit] = []
        var finished = false
        var capped = false
        var callbackCount = 0

        func collect(_ newHits: [SearchHit], _ isFinished: Bool, _ isCapped: Bool) {
            callbackCount += 1
            hits.append(contentsOf: newHits)
            if isFinished {
                finished = true
                capped = isCapped
            }
        }
    }

    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("SubtreeSearcherTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Fake.app/Contents"), withIntermediateDirectories: true)
        for path in [
            "needle-top.txt", "a/b/needle-deep.txt", ".needle-hidden.txt",
            "Fake.app/Contents/needle-pkg.txt", "unrelated.txt",
        ] {
            fm.createFile(atPath: root.appendingPathComponent(path).path, contents: Data())
        }
        return root
    }

    @Test func findsRecursiveMatchesSkippingHiddenAndPackages() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let collector = Collector()
        await SubtreeSearcher.search(root: root, query: "needle", includeHidden: false) {
            collector.collect($0, $1, $2)
        }
        let names = Set(collector.hits.map(\.entry.name))
        #expect(names.contains("needle-top.txt"))
        #expect(names.contains("needle-deep.txt"))
        #expect(!names.contains(".needle-hidden.txt"))
        #expect(!names.contains("needle-pkg.txt"))
        #expect(!names.contains("unrelated.txt"))
        #expect(collector.finished)
        #expect(!collector.capped)
    }

    @Test func includeHiddenFindsDotFiles() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let collector = Collector()
        await SubtreeSearcher.search(root: root, query: "needle", includeHidden: true) {
            collector.collect($0, $1, $2)
        }
        #expect(collector.hits.map(\.entry.name).contains(".needle-hidden.txt"))
    }

    @Test func capStopsEarlyAndReportsCapped() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("SubtreeSearcherTests-cap-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for index in 0..<30 {
            fm.createFile(atPath: root.appendingPathComponent("cap-\(index).txt").path, contents: Data())
        }
        let collector = Collector()
        await SubtreeSearcher.search(root: root, query: "cap", includeHidden: false, cap: 10) {
            collector.collect($0, $1, $2)
        }
        #expect(collector.hits.count == 10)
        #expect(collector.finished)
        #expect(collector.capped)
    }

    @Test func cancelledTaskDeliversNothing() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let collector = Collector()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await SubtreeSearcher.search(root: root, query: "needle", includeHidden: false) {
                collector.collect($0, $1, $2)
            }
        }
        await task.value
        #expect(collector.callbackCount == 0)
    }

    @Test func mergeRanksByScoreThenName() throws {
        func hit(_ name: String, _ score: Int) -> SearchHit {
            SearchHit(
                entry: FileBrowserModel.makeEntry(for: URL(fileURLWithPath: "/tmp/\(name)")),
                score: score
            )
        }
        let merged = SubtreeSearcher.merge(
            [hit("beta.txt", 5), hit("alpha.txt", 5)],
            adding: [hit("winner.txt", 9)]
        )
        #expect(merged.map(\.entry.name) == ["winner.txt", "alpha.txt", "beta.txt"])
    }

    @Test func prefixMatchOutranksScatteredMatch() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("SubtreeSearcherTests-rank-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        fm.createFile(atPath: root.appendingPathComponent("recipe-prep.pdf").path, contents: Data())
        fm.createFile(atPath: root.appendingPathComponent("report.pdf").path, contents: Data())
        let collector = Collector()
        await SubtreeSearcher.search(root: root, query: "rep", includeHidden: false) {
            collector.collect($0, $1, $2)
        }
        let ranked = SubtreeSearcher.merge([], adding: collector.hits)
        #expect(ranked.first?.entry.name == "report.pdf")
    }
}
