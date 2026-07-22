import Foundation
import Testing
@testable import MikaPanes

private struct Fixture: SortableEntry {
    var name: String
    var isDirectory = false
    var modificationDate: Date?
    var fileSize: Int64?
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

@Suite struct EntrySortingTests {

    // MARK: - Directories first

    @Test func directoriesPrecedeFilesForEveryFieldAndDirection() {
        let entries = [
            Fixture(name: "zebra.txt", modificationDate: date(500), fileSize: 900),
            Fixture(name: "Applications", isDirectory: true, modificationDate: date(100)),
            Fixture(name: "alpha.txt", modificationDate: date(300), fileSize: 10),
            Fixture(name: "zzz-folder", isDirectory: true, modificationDate: date(400)),
        ]

        for field in SortField.allCases {
            for ascending in [true, false] {
                let sorted = EntrySorting.sorted(entries, by: field, ascending: ascending)
                #expect(sorted.prefix(2).allSatisfy { $0.isDirectory },
                        "directories must come first for \(field) ascending=\(ascending)")
                #expect(sorted.suffix(2).allSatisfy { !$0.isDirectory },
                        "files must come last for \(field) ascending=\(ascending)")
            }
        }
    }

    // MARK: - Name

    @Test func nameAscendingIsCaseInsensitive() {
        let entries = [
            Fixture(name: "gamma.txt"),
            Fixture(name: "Alpha.txt"),
            Fixture(name: "beta.txt"),
        ]
        let sorted = EntrySorting.sorted(entries, by: .name, ascending: true)
        #expect(sorted.map(\.name) == ["Alpha.txt", "beta.txt", "gamma.txt"])
    }

    @Test func nameDescendingIsCaseInsensitive() {
        let entries = [
            Fixture(name: "beta.txt"),
            Fixture(name: "Gamma.txt"),
            Fixture(name: "alpha.txt"),
        ]
        let sorted = EntrySorting.sorted(entries, by: .name, ascending: false)
        #expect(sorted.map(\.name) == ["Gamma.txt", "beta.txt", "alpha.txt"])
    }

    // MARK: - Date modified

    @Test func dateAscending() {
        let entries = [
            Fixture(name: "b.txt", modificationDate: date(300)),
            Fixture(name: "a.txt", modificationDate: date(100)),
            Fixture(name: "c.txt", modificationDate: date(200)),
        ]
        let sorted = EntrySorting.sorted(entries, by: .dateModified, ascending: true)
        #expect(sorted.map(\.name) == ["a.txt", "c.txt", "b.txt"])
    }

    @Test func dateDescending() {
        let entries = [
            Fixture(name: "b.txt", modificationDate: date(300)),
            Fixture(name: "a.txt", modificationDate: date(100)),
            Fixture(name: "c.txt", modificationDate: date(200)),
        ]
        let sorted = EntrySorting.sorted(entries, by: .dateModified, ascending: false)
        #expect(sorted.map(\.name) == ["b.txt", "c.txt", "a.txt"])
    }

    // MARK: - Size

    @Test func sizeAscending() {
        let entries = [
            Fixture(name: "big.bin", fileSize: 5000),
            Fixture(name: "small.bin", fileSize: 5),
            Fixture(name: "mid.bin", fileSize: 500),
        ]
        let sorted = EntrySorting.sorted(entries, by: .size, ascending: true)
        #expect(sorted.map(\.name) == ["small.bin", "mid.bin", "big.bin"])
    }

    @Test func sizeDescending() {
        let entries = [
            Fixture(name: "small.bin", fileSize: 5),
            Fixture(name: "big.bin", fileSize: 5000),
            Fixture(name: "mid.bin", fileSize: 500),
        ]
        let sorted = EntrySorting.sorted(entries, by: .size, ascending: false)
        #expect(sorted.map(\.name) == ["big.bin", "mid.bin", "small.bin"])
    }

    // MARK: - Tie-breaks (always name ascending)

    @Test func identicalDatesTieBreakByNameAscendingInBothDirections() {
        let entries = [
            Fixture(name: "c.txt", modificationDate: date(100)),
            Fixture(name: "a.txt", modificationDate: date(100)),
            Fixture(name: "b.txt", modificationDate: date(100)),
        ]
        let expected = ["a.txt", "b.txt", "c.txt"]
        #expect(EntrySorting.sorted(entries, by: .dateModified, ascending: true).map(\.name) == expected)
        #expect(EntrySorting.sorted(entries, by: .dateModified, ascending: false).map(\.name) == expected)
    }

    @Test func identicalSizesTieBreakByNameAscendingInBothDirections() {
        let entries = [
            Fixture(name: "Charlie.bin", fileSize: 42),
            Fixture(name: "bravo.bin", fileSize: 42),
            Fixture(name: "alpha.bin", fileSize: 42),
        ]
        let expected = ["alpha.bin", "bravo.bin", "Charlie.bin"]
        #expect(EntrySorting.sorted(entries, by: .size, ascending: true).map(\.name) == expected)
        #expect(EntrySorting.sorted(entries, by: .size, ascending: false).map(\.name) == expected)
    }

    // MARK: - nil metadata

    @Test func nilDateSortsAsSmallestValue() {
        let entries = [
            Fixture(name: "dated.txt", modificationDate: date(100)),
            Fixture(name: "undated.txt", modificationDate: nil),
        ]
        let ascending = EntrySorting.sorted(entries, by: .dateModified, ascending: true)
        #expect(ascending.map(\.name) == ["undated.txt", "dated.txt"])

        let descending = EntrySorting.sorted(entries, by: .dateModified, ascending: false)
        #expect(descending.map(\.name) == ["dated.txt", "undated.txt"])
    }

    @Test func nilSizeSortsAsSmallestValue() {
        let entries = [
            Fixture(name: "sized.txt", fileSize: 0),
            Fixture(name: "unsized.txt", fileSize: nil),
        ]
        let ascending = EntrySorting.sorted(entries, by: .size, ascending: true)
        #expect(ascending.map(\.name) == ["unsized.txt", "sized.txt"])

        let descending = EntrySorting.sorted(entries, by: .size, ascending: false)
        #expect(descending.map(\.name) == ["sized.txt", "unsized.txt"])
    }

    @Test func directoriesWithNilSizeFallBackToNameTieBreakWhenSortingBySize() {
        let entries = [
            Fixture(name: "Zeta", isDirectory: true, fileSize: nil),
            Fixture(name: "file.txt", fileSize: 100),
            Fixture(name: "Alpha", isDirectory: true, fileSize: nil),
        ]
        let sorted = EntrySorting.sorted(entries, by: .size, ascending: false)
        #expect(sorted.map(\.name) == ["Alpha", "Zeta", "file.txt"])
    }
}
