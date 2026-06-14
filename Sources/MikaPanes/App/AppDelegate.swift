import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore.shared
    private let hotKeys = HotKeyManager()
    private lazy var tiler = WindowTiler()
    private lazy var overlay = OverlayController(root: settings.browserRoot)
    private let onboarding = OnboardingWindowController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(
            onOpenSettings: { [weak self] in self?.onboarding.show() },
            onQuit: { NSApp.terminate(nil) }
        )

        hotKeys.onAction = { [weak self] action in self?.handle(action) }
        hotKeys.registerDefaults(using: settings)

        // Prompt for Accessibility on first run if it isn't granted yet.
        if !PermissionsService.isAccessibilityTrusted {
            PermissionsService.requestAccessibility()
            onboarding.show()
        }
    }

    private func handle(_ action: HotKeyAction) {
        if let preset = action.tilePreset {
            tiler.apply(preset)
        } else if action == .toggleOverlay {
            overlay.toggle()
        }
    }
}
