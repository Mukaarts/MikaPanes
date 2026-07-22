import Foundation

/// Minimal shape a file-list entry must expose to be sortable. Model-free so
/// sorting stays pure Foundation and testable off the main actor.
protocol SortableEntry {
    var name: String { get }
    var isDirectory: Bool { get }
    var modificationDate: Date? { get }
    var fileSize: Int64? { get }
}

enum SortField: String, CaseIterable {
    case name, dateModified, size
}

enum EntrySorting {

    /// Sorts entries by `field` in the given direction. Directories always
    /// precede files regardless of field and direction; ties within the sort
    /// field fall back to name ascending so ordering stays deterministic.
    static func sorted<E: SortableEntry>(_ entries: [E], by field: SortField, ascending: Bool) -> [E] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }

            switch field {
            case .name:
                let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if result == .orderedSame { return false }
                return ascending ? result == .orderedAscending : result == .orderedDescending
            case .dateModified:
                let lhsDate = lhs.modificationDate ?? .distantPast
                let rhsDate = rhs.modificationDate ?? .distantPast
                if lhsDate == rhsDate { return nameTieBreak(lhs, rhs) }
                return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
            case .size:
                // nil size (typical for directories) sorts as the smallest value.
                let lhsSize = lhs.fileSize ?? -1
                let rhsSize = rhs.fileSize ?? -1
                if lhsSize == rhsSize { return nameTieBreak(lhs, rhs) }
                return ascending ? lhsSize < rhsSize : lhsSize > rhsSize
            }
        }
    }

    /// Tie-break is always name ascending, even when sorting descending.
    private static func nameTieBreak(_ lhs: some SortableEntry, _ rhs: some SortableEntry) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
