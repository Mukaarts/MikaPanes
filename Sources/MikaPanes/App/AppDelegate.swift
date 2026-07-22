import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore.shared
    private lazy var browser = BrowserWindowController(root: settings.browserRoot)

    func applicationDidFinishLaunching(_ notification: Notification) {
        browser.installMainMenu(appName: "Mika+ Panes")
        browser.showWindow()
    }

    /// Clicking the Dock icon with no open window reopens the browser window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { browser.showWindow() }
        return true
    }

    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.show()
    }
}
