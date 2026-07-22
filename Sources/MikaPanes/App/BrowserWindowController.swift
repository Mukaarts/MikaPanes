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
final class BrowserWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
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
        window.setFrameAutosaveName("MikaBrowserWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(container)
        NSApp.activate(ignoringOtherApps: true)
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
    @objc func addToFavorites(_ sender: Any?) { model.addLeadToFavorites() }
    @objc func goBack(_ sender: Any?) { model.goBack() }
    @objc func goForward(_ sender: Any?) { model.goForward() }

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
        case #selector(renameItem(_:)), #selector(duplicateItem(_:)), #selector(trashItem(_:)),
             #selector(revealItem(_:)), #selector(quickLookItem(_:)):
            return model.hasSelection
        case #selector(copyItem(_:)), #selector(cutItem(_:)):
            return activeFieldEditor != nil || model.hasSelection
        case #selector(pasteItem(_:)):
            return activeFieldEditor != nil || model.pasteboardHasFileURLs
        case #selector(moveItemHere(_:)):
            return model.pasteboardHasFileURLs
        case #selector(addToFavorites(_:)):
            return model.canAddLeadToFavorites
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = model.showHiddenFiles ? .on : .off
            return true
        default:
            return true
        }
    }

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
        // target nil: resolved via the responder chain down to the AppDelegate.
        appMenu.addItem(withTitle: "Settings…",
                        action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
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
        let newFolderItem = addItem(to: fileMenu, "New Folder", #selector(newFolder(_:)), "n")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, "Reveal in Finder", #selector(revealItem(_:)), "r")
        addItem(to: fileMenu, "Quick Look", #selector(quickLookItem(_:)), "y")
        fileMenu.addItem(.separator())
        let renameItem = addItem(to: fileMenu, "Rename",
                                 #selector(renameItem(_:)),
                                 String(UnicodeScalar(NSF2FunctionKey)!))
        renameItem.keyEquivalentModifierMask = []
        addItem(to: fileMenu, "Duplicate", #selector(duplicateItem(_:)), "d")
        let favorite = addItem(to: fileMenu, "Add to Favorites", #selector(addToFavorites(_:)), "t")
        favorite.keyEquivalentModifierMask = [.command, .control]
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
        // Undo/redo resolve through the responder chain: the field editor
        // supplies its own manager during a rename, the window delegate
        // supplies the model's one otherwise.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        addItem(to: editMenu, "Cut", #selector(cutItem(_:)), "x")
        addItem(to: editMenu, "Copy", #selector(copyItem(_:)), "c")
        addItem(to: editMenu, "Paste", #selector(pasteItem(_:)), "v")
        let moveHere = addItem(to: editMenu, "Move Item Here", #selector(moveItemHere(_:)), "v")
        moveHere.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(.separator())
        addItem(to: editMenu, "Select All", #selector(selectAllItems(_:)), "a")

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let hidden = addItem(to: viewMenu, "Show Hidden Files", #selector(toggleHiddenFiles(_:)), ".")
        hidden.keyEquivalentModifierMask = [.command, .shift]

        // Go menu
        let goItem = NSMenuItem()
        mainMenu.addItem(goItem)
        let goMenu = NSMenu(title: "Go")
        goItem.submenu = goMenu
        addItem(to: goMenu, "Back", #selector(goBack(_:)), "[")
        addItem(to: goMenu, "Forward", #selector(goForward(_:)), "]")
        goMenu.addItem(.separator())
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
