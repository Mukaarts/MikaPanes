import AppKit
import Carbon.HIToolbox
import SwiftUI

/// An NSView that captures raw key events and forwards them to a handler. Used
/// as the window's content view so arrow/enter/typing drive the browser while
/// the SwiftUI subtree handles drawing and mouse clicks.
final class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
}

/// Owns one browser window and its keyboard handling. Menu items reach the
/// controller of the key window via the responder chain (the controller is its
/// window's delegate); the menu itself is built once in `MainMenuBuilder`.
@MainActor
final class BrowserWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private let model: FileBrowserModel
    private let onClose: (BrowserWindowController) -> Void
    private(set) var window: NSWindow?

    init(root: URL, onClose: @escaping (BrowserWindowController) -> Void = { _ in }) {
        self.model = FileBrowserModel(root: root)
        self.onClose = onClose
        super.init()
        model.openInNewWindow = { url in
            WindowManager.shared.newWindow(root: url)
        }
        model.openInNewTab = { [weak self] url in
            WindowManager.shared.newTab(root: url, relativeTo: self)
        }
    }

    // MARK: - Window

    /// Creates the window on first call (not yet visible) and returns it.
    /// Frame placement (autosave vs. cascade) is the WindowManager's job.
    @discardableResult
    func loadWindow() -> NSWindow {
        if let window { return window }

        let container = KeyCaptureView()
        container.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }

        let hosting = NSHostingView(
            rootView: BrowserView(
                model: model,
                favoritesStore: model.favoritesStore,
                keyHandler: { [weak self] event in self?.handleKey(event) ?? false }
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mika+ Panes"
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "MikaBrowser"
        window.delegate = self
        self.window = window
        return window
    }

    func showWindow() {
        let window = loadWindow()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.teardown()
        window?.delegate = nil
        onClose(self)
    }

    /// After a tab switch the window can end up with itself as first
    /// responder; hand focus to the content view so typing works right away.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window, window.firstResponder === window else { return }
        window.makeFirstResponder(window.contentView)
    }

    /// File-operation undo lives in the model. While an inline rename is active
    /// the field editor is first responder and supplies its own undo manager,
    /// so ⌘Z does text undo there — same as Finder.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        model.undoManager
    }

    // MARK: - Keyboard

    /// Handles keys that aren't menu key-equivalents (the menu owns the ⌘ file
    /// actions). Returns whether the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let chars = event.charactersIgnoringModifiers ?? ""

        if cmd {
            // ⌘1…⌘9 jump to the matching sidebar favorite; swallow other ⌘ combos
            // so they aren't mistaken for typed search input.
            if let digit = Int(chars), (1...9).contains(digit) {
                model.jumpToFavorite(digit - 1)
                return true
            }
            return false
        }

        switch Int(event.keyCode) {
        case kVK_UpArrow:
            model.moveSelection(by: -1, extending: shift); return true
        case kVK_DownArrow:
            model.moveSelection(by: 1, extending: shift); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.activateSelection(); return true
        case kVK_Delete:
            model.backspace(); return true
        case kVK_Space:
            model.quickLookSelection(); return true
        case kVK_Escape:
            model.clearQuery(); return true
        case kVK_F2:
            model.beginRename(); return true
        default:
            break
        }

        // Printable input feeds the live fuzzy search.
        if let scalar = chars.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F,
           scalar.properties.generalCategory != .privateUse {
            model.appendToQuery(chars)
            return true
        }
        return false
    }

    // MARK: - Menu actions (file operations)

    /// While the rename field editor is active, text-editing commands must act
    /// on the text, not on files; forward and bail out in that case.
    private var activeFieldEditor: NSTextView? {
        window?.firstResponder as? NSTextView
    }

    @objc func revealItem(_ sender: Any?) { model.revealSelection() }
    @objc func quickLookItem(_ sender: Any?) { model.quickLookSelection() }
    @objc func trashItem(_ sender: Any?) { model.trashSelection() }
    @objc func newFolder(_ sender: Any?) { model.createNewFolder() }
    @objc func renameItem(_ sender: Any?) { model.beginRename() }
    @objc func duplicateItem(_ sender: Any?) { model.duplicateSelection() }
    @objc func moveItemHere(_ sender: Any?) { model.moveItemHere() }
    @objc func toggleHiddenFiles(_ sender: Any?) { model.toggleHiddenFiles() }
    @objc func goUp(_ sender: Any?) { model.goToParent() }
    @objc func goHome(_ sender: Any?) { model.goHome() }
    @objc func goBack(_ sender: Any?) { model.goBack() }
    @objc func goForward(_ sender: Any?) { model.goForward() }
    @objc func addToFavorites(_ sender: Any?) { model.addLeadToFavorites() }
    @objc func cycleSearchScope(_ sender: Any?) { model.cycleSearchScope() }

    @objc func newWindowForTab(_ sender: Any?) {
        WindowManager.shared.newTab(relativeTo: self)
    }

    @objc func copyItem(_ sender: Any?) {
        if let editor = activeFieldEditor { editor.copy(sender); return }
        model.copySelection()
    }

    @objc func cutItem(_ sender: Any?) {
        if let editor = activeFieldEditor { editor.cut(sender); return }
        model.cutSelection()
    }

    @objc func pasteItem(_ sender: Any?) {
        if let editor = activeFieldEditor { editor.paste(sender); return }
        model.paste()
    }

    @objc func selectAllItems(_ sender: Any?) {
        if let editor = activeFieldEditor { editor.selectAll(sender); return }
        model.selectAll()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack(_:)):
            return model.canGoBack
        case #selector(goForward(_:)):
            return model.canGoForward
        case #selector(trashItem(_:)), #selector(revealItem(_:)), #selector(quickLookItem(_:)):
            return model.hasSelection
        case #selector(renameItem(_:)), #selector(duplicateItem(_:)):
            return model.hasSelection && !model.isDeepSearchActive
        case #selector(newFolder(_:)):
            return !model.isDeepSearchActive
        case #selector(copyItem(_:)):
            return activeFieldEditor != nil || model.hasSelection
        case #selector(cutItem(_:)):
            return activeFieldEditor != nil || (model.hasSelection && !model.isDeepSearchActive)
        case #selector(pasteItem(_:)):
            return activeFieldEditor != nil
                || (model.pasteboardHasFileURLs && !model.isDeepSearchActive)
        case #selector(moveItemHere(_:)):
            return model.pasteboardHasFileURLs && !model.isDeepSearchActive
        case #selector(addToFavorites(_:)):
            return model.canAddLeadToFavorites
        case #selector(cycleSearchScope(_:)):
            return !model.query.isEmpty
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = model.showHiddenFiles ? .on : .off
            return true
        default:
            return true
        }
    }
}
