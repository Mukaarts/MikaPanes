import Foundation

/// Typed wrapper over `UserDefaults` for persisted settings.
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private enum Key {
        static let browserRoot = "browser.root"
        static let sortField = "browser.sortField"
        static let sortAscending = "browser.sortAscending"
        static let showHidden = "browser.showHidden"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Root directory the browser opens at (home by default).
    var browserRoot: URL {
        get {
            if let path = defaults.string(forKey: Key.browserRoot) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }
        set {
            defaults.set(newValue.path, forKey: Key.browserRoot)
        }
    }

    /// Column the file list is sorted by.
    var sortField: SortField {
        get { defaults.string(forKey: Key.sortField).flatMap(SortField.init(rawValue:)) ?? .name }
        set { defaults.set(newValue.rawValue, forKey: Key.sortField) }
    }

    var sortAscending: Bool {
        get { defaults.object(forKey: Key.sortAscending) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.sortAscending) }
    }

    var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHidden) }
        set { defaults.set(newValue, forKey: Key.showHidden) }
    }
}
