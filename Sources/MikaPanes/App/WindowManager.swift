import AppKit

/// Owns every browser window controller. The first window keeps the frame
/// autosave; later windows cascade from it. Closing a window releases its
/// controller here.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private(set) var controllers: [BrowserWindowController] = []
    private var cascadePoint = NSPoint.zero
    private static let primaryFrameName = "MikaBrowserWindow"

    @discardableResult
    func newWindow(root: URL? = nil) -> BrowserWindowController {
        let isPrimary = controllers.isEmpty
        let controller = makeController(root: root)
        let window = controller.loadWindow()
        if isPrimary {
            if !window.setFrameUsingName(Self.primaryFrameName) { window.center() }
            window.setFrameAutosaveName(Self.primaryFrameName)
        } else {
            if let reference = NSApp.keyWindow ?? controllers.first?.window {
                window.setFrame(reference.frame, display: false)
            }
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
        controller.showWindow()
        return controller
    }

    /// Opens a new browser as a native tab of the host window (or the key
    /// window); falls back to a regular window when none exists.
    func newTab(root: URL? = nil, relativeTo host: BrowserWindowController? = nil) {
        guard let hostWindow = host?.window ?? NSApp.keyWindow ?? controllers.last?.window else {
            newWindow(root: root)
            return
        }
        let controller = makeController(root: root)
        let window = controller.loadWindow()
        hostWindow.addTabbedWindow(window, ordered: .above)
        controller.showWindow()
    }

    /// Dock-icon click with no visible window: front the last one or start fresh.
    func reopen() {
        if let last = controllers.last {
            last.showWindow()
        } else {
            newWindow()
        }
    }

    private func makeController(root: URL?) -> BrowserWindowController {
        let controller = BrowserWindowController(
            root: root ?? SettingsStore.shared.browserRoot
        ) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        return controller
    }
}
