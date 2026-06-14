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

/// Owns the main window, its keyboard handling and the app's main menu.
@MainActor
final class BrowserWindowController: NSObject {
    private let model: FileBrowserModel
    private var window: NSWindow?

    init(root: URL) {
        self.model = FileBrowserModel(root: root)
        super.init()
    }

    // MARK: - Window

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let container = KeyCaptureView()
        container.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }

        let hosting = NSHostingView(rootView: BrowserView(model: model))
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
        window.setFrameAutosaveName("MikaBrowserWindow")
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(container)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Keyboard

    /// Handles keys that aren't menu key-equivalents (the menu owns the ⌘ file
    /// actions). Returns whether the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
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
            model.moveSelection(by: -1); return true
        case kVK_DownArrow:
            model.moveSelection(by: 1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.activateSelection(); return true
        case kVK_Delete:
            model.backspace(); return true
        case kVK_Space:
            model.quickLookSelection(); return true
        case kVK_Escape:
            model.clearQuery(); return true
        default:
            break
        }

        // Printable input feeds the live fuzzy search.
        if let scalar = chars.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F {
            model.appendToQuery(chars)
            return true
        }
        return false
    }

    // MARK: - Menu actions (file operations)

    @objc func revealItem(_ sender: Any?) { model.revealSelection() }
    @objc func quickLookItem(_ sender: Any?) { model.quickLookSelection() }
    @objc func trashItem(_ sender: Any?) { model.trashSelection() }
    @objc func copyItem(_ sender: Any?) { model.copySelection() }
    @objc func cutItem(_ sender: Any?) { model.cutSelection() }
    @objc func pasteItem(_ sender: Any?) { model.paste() }
    @objc func goUp(_ sender: Any?) { model.goToParent() }
    @objc func goHome(_ sender: Any?) { model.jumpToFavorite(0) }

    // MARK: - Main menu

    /// A regular Dock app needs an explicit menu bar; build a minimal Finder-like one.
    func installMainMenu(appName: String) {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                        action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        addItem(to: fileMenu, "Reveal in Finder", #selector(revealItem(_:)), "r")
        addItem(to: fileMenu, "Quick Look", #selector(quickLookItem(_:)), "y")
        fileMenu.addItem(.separator())
        let trash = addItem(to: fileMenu, "Move to Trash", #selector(trashItem(_:)), "\u{7F}")
        trash.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu (file clipboard, Finder-style)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        addItem(to: editMenu, "Copy", #selector(copyItem(_:)), "c")
        addItem(to: editMenu, "Cut", #selector(cutItem(_:)), "x")
        addItem(to: editMenu, "Paste", #selector(pasteItem(_:)), "v")

        // Go menu
        let goItem = NSMenuItem()
        mainMenu.addItem(goItem)
        let goMenu = NSMenu(title: "Go")
        goItem.submenu = goMenu
        let up = addItem(to: goMenu, "Enclosing Folder", #selector(goUp(_:)),
                         String(UnicodeScalar(NSUpArrowFunctionKey)!))
        up.keyEquivalentModifierMask = [.command]
        let home = addItem(to: goMenu, "Home", #selector(goHome(_:)), "h")
        home.keyEquivalentModifierMask = [.command, .shift]

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }
}
