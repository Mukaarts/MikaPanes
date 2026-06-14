import AppKit

// A regular Dock app (no LSUIElement): shows a Dock icon, a menu bar and a
// normal window. Top-level code runs on the main thread; assert that so we can
// touch main-actor-isolated API directly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
