import AppKit

/// Builds the app's main menu once at launch. Window-scoped items use
/// target nil, so the responder chain routes them to the key window's
/// `BrowserWindowController` (each controller is its window's delegate and
/// thereby part of that chain, including `validateMenuItem`). App-scoped
/// items (`newWindow:`, `showPreferences:`) resolve to the AppDelegate at the
/// end of the chain — they stay enabled when no browser window is key.
@MainActor
enum MainMenuBuilder {

    static func install(appName: String) {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu(appName: appName)))
        mainMenu.addItem(submenu(fileMenu()))
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(viewMenu()))
        mainMenu.addItem(submenu(goMenu()))
        let windows = windowMenu()
        mainMenu.addItem(submenu(windows))
        NSApp.windowsMenu = windows
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menus

    private static func appMenu(appName: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), mask: []))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showPreferences(_:)), ","))
        menu.addItem(.separator())
        menu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", mask: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), mask: []))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(item("New Tab", #selector(BrowserWindowController.newWindowForTab(_:)), "t"))
        menu.addItem(item("New Folder", #selector(BrowserWindowController.newFolder(_:)), "n", mask: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Reveal in Finder", #selector(BrowserWindowController.revealItem(_:)), "r"))
        menu.addItem(item("Quick Look", #selector(BrowserWindowController.quickLookItem(_:)), "y"))
        menu.addItem(.separator())
        menu.addItem(item("Rename", #selector(BrowserWindowController.renameItem(_:)),
                          String(UnicodeScalar(NSF2FunctionKey)!), mask: []))
        menu.addItem(item("Duplicate", #selector(BrowserWindowController.duplicateItem(_:)), "d"))
        menu.addItem(item("Add to Favorites", #selector(BrowserWindowController.addToFavorites(_:)), "t", mask: [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(item("Move to Trash", #selector(BrowserWindowController.trashItem(_:)), "\u{7F}"))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        // Undo/redo resolve through the responder chain: the field editor
        // supplies its own manager during a rename, the window delegate
        // supplies the model's one otherwise.
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "Z"))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(BrowserWindowController.cutItem(_:)), "x"))
        menu.addItem(item("Copy", #selector(BrowserWindowController.copyItem(_:)), "c"))
        menu.addItem(item("Paste", #selector(BrowserWindowController.pasteItem(_:)), "v"))
        menu.addItem(item("Move Item Here", #selector(BrowserWindowController.moveItemHere(_:)), "v", mask: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(BrowserWindowController.selectAllItems(_:)), "a"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Show Hidden Files", #selector(BrowserWindowController.toggleHiddenFiles(_:)), ".", mask: [.command, .shift]))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        menu.addItem(item("Back", #selector(BrowserWindowController.goBack(_:)), "["))
        menu.addItem(item("Forward", #selector(BrowserWindowController.goForward(_:)), "]"))
        menu.addItem(.separator())
        menu.addItem(item("Enclosing Folder", #selector(BrowserWindowController.goUp(_:)),
                          String(UnicodeScalar(NSUpArrowFunctionKey)!)))
        menu.addItem(item("Home", #selector(BrowserWindowController.goHome(_:)), "h", mask: [.command, .shift]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), mask: []))
        menu.addItem(.separator())
        menu.addItem(item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), mask: []))
        menu.addItem(item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), mask: []))
        menu.addItem(item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:)), mask: []))
        menu.addItem(item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)), mask: []))
        return menu
    }

    // MARK: - Helpers

    private static func item(
        _ title: String, _ action: Selector?, _ key: String = "",
        mask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mask
        return item
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
