import Foundation

/// Typed wrapper over `UserDefaults` for persisted settings.
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private enum Key {
        static let browserRoot = "browser.root"
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
}
