import AppKit
import SwiftUI

/// Singleton owner of the Settings window (⌘,). The window is created lazily
/// once and re-shown afterwards; ⌘W closes it via the regular responder chain.
@MainActor
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingView(
                rootView: PreferencesView(favoritesStore: .shared, settings: .shared)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            if !window.setFrameUsingName("MikaPreferences") { window.center() }
            window.setFrameAutosaveName("MikaPreferences")
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
