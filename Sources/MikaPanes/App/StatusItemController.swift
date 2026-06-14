import AppKit

/// The menu bar presence: a status item whose menu shows live permission status
/// and the main actions.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.2x2",
                accessibilityDescription: "Mika+ Panes"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuild the menu each time it opens so permission status is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(header("Mika+ Panes"))
        menu.addItem(.separator())

        menu.addItem(statusRow(
            title: "Accessibility",
            granted: PermissionsService.isAccessibilityTrusted
        ))
        menu.addItem(statusRow(
            title: "Full Disk Access",
            granted: PermissionsService.hasFullDiskAccess
        ))

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Permissions & Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Mika+ Panes", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Rows

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func statusRow(title: String, granted: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(granted ? "✓ granted" : "✗ missing")",
                              action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { onQuit() }
}
