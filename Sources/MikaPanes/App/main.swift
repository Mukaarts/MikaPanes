import AppKit

// LSUIElement is set in Info.plist; `.accessory` is the runtime equivalent so the
// app also behaves correctly when launched as a bare binary during development.
//
// Top-level code runs on the main thread; assert that to the compiler so we can
// touch main-actor-isolated API (NSApplication, AppDelegate) directly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
