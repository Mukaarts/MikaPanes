import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuBuilder.install(appName: "Mika+ Panes")
        WindowManager.shared.newWindow()
    }

    /// Clicking the Dock icon with no open window reopens a browser window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.reopen() }
        return true
    }

    @objc func newWindow(_ sender: Any?) {
        WindowManager.shared.newWindow()
    }

    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.show()
    }
}
