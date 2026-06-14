import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A floating, non-activating panel that can still become key (so it receives
/// keystrokes) without activating the app or stealing focus from the front app.
final class OverlayPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    /// Esc and ⌘. route here.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Owns the overlay panel lifecycle, hosts the SwiftUI view, and translates key
/// events into `FileBrowserModel` actions.
@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private let model: FileBrowserModel

    init(root: URL) {
        self.model = FileBrowserModel(root: root)
    }

    // MARK: - Lifecycle

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        if model.sourceMode == .finderSelection {
            model.refreshFinderSelection()
        }

        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel construction

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.frame = panel.contentLayoutRect
        panel.contentView = hosting

        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onCancel = { [weak self] in self?.hide() }
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + frame.height * 0.62 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Key handling

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let chars = event.charactersIgnoringModifiers ?? ""

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
            return true
        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return true
        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.activateSelection() { hide() }
            return true
        case kVK_Delete:
            if cmd { model.trashTargets() } else { model.backspace() }
            return true
        case kVK_Space:
            model.quickLookTargets()
            return true
        case kVK_Tab:
            model.toggleSourceMode()
            return true
        default:
            break
        }

        if cmd {
            switch chars.lowercased() {
            case "r": model.revealTargets()
            case "c": model.copyTargetsHere()
            case "m": model.moveTargetsHere()
            default: break
            }
            return true
        }

        // Printable input feeds the live fuzzy query (own-browser mode only).
        if model.sourceMode == .ownBrowser,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F {
            model.appendToQuery(chars)
            return true
        }
        return false
    }
}
