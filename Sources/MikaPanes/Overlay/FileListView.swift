import AppKit
import SwiftUI

/// AppKit-backed file list. NSTableView provides multi-selection, sortable
/// column headers, native inline rename via the field editor, Finder-style
/// context menus (clickedRow semantics) and row-targeted drag & drop — the
/// parts SwiftUI's List/Table can't do reliably on macOS 14.
struct FileListView: NSViewRepresentable {
    @ObservedObject var model: FileBrowserModel
    let keyHandler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, keyHandler: keyHandler)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(
            entries: model.displayedEntries,
            selectedURLs: model.selectedURLs,
            leadURL: model.leadSelectionURL,
            renamingURL: model.renamingURL,
            cutURLs: model.cutPendingURLs,
            sortField: model.sortField,
            sortAscending: model.sortAscending,
            isSearchMode: model.isDeepSearchActive,
            locationRoot: model.currentURL
        )
    }
}

/// NSTableView subclass that funnels raw key events into the same handler the
/// window's KeyCaptureView uses, so keyboard behaviour is identical no matter
/// which of the two is first responder.
final class FileTableView: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?
    var menuBuilder: ((Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return menuBuilder?(row(at: point))
    }

    override func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .move]
    }
}

extension FileListView {

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

        private let model: FileBrowserModel
        private let keyHandler: (NSEvent) -> Bool
        private weak var tableView: FileTableView?

        private var entries: [FileBrowserModel.Entry] = []
        private var cutURLs: Set<URL> = []
        private var isSyncingSelection = false
        private var isUpdatingSortDescriptors = false
        private var activeRenameURL: URL?
        private var isCancellingRename = false
        private var isSearchMode = false
        private var locationRoot: URL?
        private static let locationColumnID = NSUserInterfaceItemIdentifier("location")

        init(model: FileBrowserModel, keyHandler: @escaping (NSEvent) -> Bool) {
            self.model = model
            self.keyHandler = keyHandler
        }

        // MARK: - View construction

        func makeScrollView() -> NSScrollView {
            let table = FileTableView()
            table.dataSource = self
            table.delegate = self
            table.keyHandler = keyHandler
            table.menuBuilder = { [weak self] row in self?.buildMenu(forRow: row) }
            table.allowsMultipleSelection = true
            table.allowsColumnReordering = false
            table.usesAlternatingRowBackgroundColors = false
            table.style = .inset
            table.rowHeight = 26
            table.focusRingType = .none
            table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
            table.target = self
            table.doubleAction = #selector(didDoubleClick(_:))
            table.registerForDraggedTypes([.fileURL])

            let nameColumn = NSTableColumn(identifier: .init(SortField.name.rawValue))
            nameColumn.title = "Name"
            nameColumn.minWidth = 160
            nameColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: SortField.name.rawValue, ascending: true
            )
            table.addTableColumn(nameColumn)

            let dateColumn = NSTableColumn(identifier: .init(SortField.dateModified.rawValue))
            dateColumn.title = "Date Modified"
            dateColumn.width = 150
            dateColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: SortField.dateModified.rawValue, ascending: false
            )
            table.addTableColumn(dateColumn)

            let sizeColumn = NSTableColumn(identifier: .init(SortField.size.rawValue))
            sizeColumn.title = "Size"
            sizeColumn.width = 80
            sizeColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: SortField.size.rawValue, ascending: false
            )
            table.addTableColumn(sizeColumn)

            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            table.backgroundColor = .clear
            tableView = table
            return scroll
        }

        // MARK: - State sync (model → table)

        func apply(
            entries newEntries: [FileBrowserModel.Entry],
            selectedURLs: Set<URL>,
            leadURL: URL?,
            renamingURL: URL?,
            cutURLs newCutURLs: Set<URL>,
            sortField: SortField,
            sortAscending: Bool,
            isSearchMode newSearchMode: Bool,
            locationRoot newLocationRoot: URL
        ) {
            guard let table = tableView else { return }

            locationRoot = newLocationRoot
            if newSearchMode != isSearchMode {
                isSearchMode = newSearchMode
                updateLocationColumn(in: table)
            }

            let entriesChanged = newEntries != entries
            let cutChanged = newCutURLs != cutURLs
            entries = newEntries
            cutURLs = newCutURLs
            if entriesChanged || cutChanged {
                isSyncingSelection = true
                table.reloadData()
                isSyncingSelection = false
            }

            let current = table.sortDescriptors.first
            if !isSearchMode,
               current?.key != sortField.rawValue || current?.ascending != sortAscending {
                isUpdatingSortDescriptors = true
                table.sortDescriptors = [
                    NSSortDescriptor(key: sortField.rawValue, ascending: sortAscending)
                ]
                isUpdatingSortDescriptors = false
            }

            let desired = IndexSet(entries.indices.filter { selectedURLs.contains(entries[$0].url) })
            if table.selectedRowIndexes != desired {
                isSyncingSelection = true
                table.selectRowIndexes(desired, byExtendingSelection: false)
                isSyncingSelection = false
            }
            if let lead = leadURL, let row = entries.firstIndex(where: { $0.url == lead }) {
                table.scrollRowToVisible(row)
            }

            if let target = renamingURL {
                if target != activeRenameURL, let row = entries.firstIndex(where: { $0.url == target }) {
                    activeRenameURL = target
                    beginEditing(row: row)
                }
            } else {
                activeRenameURL = nil
            }
        }

        /// Search results are ranked by score, so header sorting makes no
        /// sense there; the extra Location column shows where a hit lives.
        private func updateLocationColumn(in table: NSTableView) {
            let existing = table.tableColumns.firstIndex { $0.identifier == Self.locationColumnID }
            if isSearchMode, existing == nil {
                let column = NSTableColumn(identifier: Self.locationColumnID)
                column.title = "Location"
                column.width = 200
                table.addTableColumn(column)
                table.moveColumn(table.numberOfColumns - 1, toColumn: 1)
            } else if !isSearchMode, let index = existing {
                table.removeTableColumn(table.tableColumns[index])
            }
        }

        // MARK: - Data source

        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

        func tableView(
            _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
        ) -> NSView? {
            guard entries.indices.contains(row), let identifier = tableColumn?.identifier else {
                return nil
            }
            if identifier == Self.locationColumnID {
                return detailCell(
                    text: locationText(for: entries[row]), identifier: "locationCell", in: tableView
                )
            }
            guard let field = SortField(rawValue: identifier.rawValue) else { return nil }
            let entry = entries[row]
            switch field {
            case .name:
                return nameCell(for: entry, in: tableView)
            case .dateModified:
                let text = entry.modificationDate.map { Self.dateFormatter.string(from: $0) } ?? "--"
                return detailCell(text: text, identifier: "dateCell", in: tableView)
            case .size:
                let text = entry.isDirectory
                    ? "--"
                    : entry.fileSize.map { Self.sizeFormatter.string(fromByteCount: $0) } ?? "--"
                return detailCell(text: text, identifier: "sizeCell", in: tableView)
            }
        }

        /// Parent folder of a hit: relative to the searched root when inside
        /// it, otherwise ~-abbreviated.
        private func locationText(for entry: FileBrowserModel.Entry) -> String {
            let parent = entry.url.deletingLastPathComponent().path
            if let root = locationRoot?.standardizedFileURL.path {
                if parent == root { return "·" }
                if parent.hasPrefix(root + "/") { return String(parent.dropFirst(root.count + 1)) }
            }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if parent == home { return "~" }
            if parent.hasPrefix(home + "/") { return "~/" + parent.dropFirst(home.count + 1) }
            return parent
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()

        private static let sizeFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()

        private func nameCell(for entry: FileBrowserModel.Entry, in table: NSTableView) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("nameCell")
            let cell: NSTableCellView
            if let reused = table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                let text = NSTextField(labelWithString: "")
                text.translatesAutoresizingMaskIntoConstraints = false
                text.lineBreakMode = .byTruncatingMiddle
                text.delegate = self
                cell.addSubview(image)
                cell.addSubview(text)
                cell.imageView = image
                cell.textField = text
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
            icon.size = NSSize(width: 16, height: 16)
            cell.imageView?.image = icon
            cell.textField?.stringValue = entry.name
            cell.textField?.isEditable = false
            let dimmed = entry.isHidden || cutURLs.contains(entry.url.standardizedFileURL)
            cell.imageView?.alphaValue = dimmed ? 0.45 : 1
            cell.textField?.alphaValue = dimmed ? 0.55 : 1
            return cell
        }

        private func detailCell(text: String, identifier: String, in table: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier(identifier)
            let cell: NSTableCellView
            if let reused = table.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = id
                let field = NSTextField(labelWithString: "")
                field.translatesAutoresizingMaskIntoConstraints = false
                field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                field.textColor = .secondaryLabelColor
                field.lineBreakMode = .byTruncatingTail
                cell.addSubview(field)
                cell.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = text
            return cell
        }

        // MARK: - Selection (table → model)

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table = tableView else { return }
            let urls = Set(table.selectedRowIndexes.compactMap { index in
                entries.indices.contains(index) ? entries[index].url : nil
            })
            let lead: URL? = entries.indices.contains(table.selectedRow)
                ? entries[table.selectedRow].url
                : urls.first
            model.setSelection(urls, lead: lead)
        }

        // MARK: - Sorting

        func tableView(
            _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard !isUpdatingSortDescriptors, !isSearchMode,
                  let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let field = SortField(rawValue: key) else { return }
            model.setSort(field: field, ascending: descriptor.ascending)
        }

        // MARK: - Open

        @objc private func didDoubleClick(_ sender: Any?) {
            guard let table = tableView, table.clickedRow >= 0 else { return }
            model.activateSelection()
        }

        // MARK: - Inline rename

        private func beginEditing(row: Int) {
            guard let table = tableView else { return }
            table.scrollRowToVisible(row)
            guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let textField = cell.textField else { return }
            textField.isEditable = true
            textField.window?.makeFirstResponder(textField)
            if let editor = textField.currentEditor() {
                // Finder-style: preselect the base name, leave the extension.
                let name = textField.stringValue as NSString
                let base = name.deletingPathExtension as NSString
                editor.selectedRange = NSRange(location: 0, length: base.length)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            if isCancellingRename { return }
            guard model.renamingURL != nil else { return }
            textField.isEditable = false
            if model.commitRename(to: textField.stringValue) {
                restoreKeyFocus()
            } else {
                // Rename failed (e.g. name collision): reopen the editor.
                textField.isEditable = true
                textField.window?.makeFirstResponder(textField)
            }
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  model.renamingURL != nil,
                  let textField = control as? NSTextField else { return false }
            isCancellingRename = true
            textField.abortEditing()
            isCancellingRename = false
            textField.isEditable = false
            if let url = model.renamingURL, let entry = entries.first(where: { $0.url == url }) {
                textField.stringValue = entry.name
            }
            model.cancelRename()
            restoreKeyFocus()
            return true
        }

        /// Hands keyboard focus back to the window's KeyCaptureView (its content
        /// view) so typing drives the fuzzy search again after a rename.
        private func restoreKeyFocus() {
            guard let window = tableView?.window else { return }
            window.makeFirstResponder(window.contentView)
        }

        // MARK: - Context menu

        private func buildMenu(forRow row: Int) -> NSMenu {
            let menu = NSMenu()
            if row >= 0, entries.indices.contains(row) {
                // Finder semantics: right-clicking outside the selection
                // retargets it to the clicked row.
                if let table = tableView, !table.selectedRowIndexes.contains(row) {
                    let url = entries[row].url
                    isSyncingSelection = true
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    isSyncingSelection = false
                    model.setSelection([url], lead: url)
                }
                if isSearchMode {
                    // Deep-search results allow the read-mostly actions only.
                    addItem(to: menu, "Open", #selector(menuOpen))
                    if entries[row].isDirectory {
                        addItem(to: menu, "Open in New Tab", #selector(menuOpenInNewTab))
                        addItem(to: menu, "Open in New Window", #selector(menuOpenInNewWindow))
                    }
                    menu.addItem(.separator())
                    addItem(to: menu, "Reveal in Finder", #selector(menuReveal))
                    addItem(to: menu, "Quick Look", #selector(menuQuickLook))
                    menu.addItem(.separator())
                    addItem(to: menu, "Copy", #selector(menuCopy))
                    menu.addItem(.separator())
                    addItem(to: menu, "Move to Trash", #selector(menuTrash))
                    return menu
                }
                addItem(to: menu, "Open", #selector(menuOpen))
                if entries[row].isDirectory {
                    addItem(to: menu, "Open in New Tab", #selector(menuOpenInNewTab))
                    addItem(to: menu, "Open in New Window", #selector(menuOpenInNewWindow))
                }
                menu.addItem(.separator())
                if model.canAddLeadToFavorites {
                    addItem(to: menu, "Add to Favorites", #selector(menuAddToFavorites))
                }
                addItem(to: menu, "Rename", #selector(menuRename))
                addItem(to: menu, "Duplicate", #selector(menuDuplicate))
                addItem(to: menu, "Reveal in Finder", #selector(menuReveal))
                addItem(to: menu, "Quick Look", #selector(menuQuickLook))
                menu.addItem(.separator())
                addItem(to: menu, "Copy", #selector(menuCopy))
                addItem(to: menu, "Cut", #selector(menuCut))
                if model.pasteboardHasFileURLs {
                    addItem(to: menu, "Paste", #selector(menuPaste))
                }
                menu.addItem(.separator())
                addItem(to: menu, "Move to Trash", #selector(menuTrash))
            } else if !isSearchMode {
                addItem(to: menu, "New Folder", #selector(menuNewFolder))
                if model.pasteboardHasFileURLs {
                    addItem(to: menu, "Paste", #selector(menuPaste))
                }
            }
            return menu
        }

        private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        @objc private func menuOpen(_ sender: Any?) { model.activateSelection() }
        @objc private func menuAddToFavorites(_ sender: Any?) { model.addLeadToFavorites() }

        @objc private func menuOpenInNewTab(_ sender: Any?) {
            if let entry = model.leadEntry, entry.isDirectory { model.openInNewTab?(entry.url) }
        }

        @objc private func menuOpenInNewWindow(_ sender: Any?) {
            if let entry = model.leadEntry, entry.isDirectory { model.openInNewWindow?(entry.url) }
        }
        @objc private func menuRename(_ sender: Any?) { model.beginRename() }
        @objc private func menuDuplicate(_ sender: Any?) { model.duplicateSelection() }
        @objc private func menuReveal(_ sender: Any?) { model.revealSelection() }
        @objc private func menuQuickLook(_ sender: Any?) { model.quickLookSelection() }
        @objc private func menuCopy(_ sender: Any?) { model.copySelection() }
        @objc private func menuCut(_ sender: Any?) { model.cutSelection() }
        @objc private func menuPaste(_ sender: Any?) { model.paste() }
        @objc private func menuTrash(_ sender: Any?) { model.trashSelection() }
        @objc private func menuNewFolder(_ sender: Any?) { model.createNewFolder() }

        // MARK: - Drag out

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard entries.indices.contains(row) else { return nil }
            return entries[row].url as NSURL
        }

        // MARK: - Drop in

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard !isSearchMode else { return [] }
            let urls = fileURLs(from: info)
            guard !urls.isEmpty else { return [] }
            var destination = model.currentURL
            if dropOperation == .on, entries.indices.contains(row), entries[row].isDirectory {
                destination = entries[row].url
            } else {
                // Anywhere else (between rows, empty space) targets the folder itself.
                tableView.setDropRow(-1, dropOperation: .on)
            }
            let copying = wantsCopy(info)
            guard !model.validDropTargets(urls, destination: destination, copying: copying).isEmpty else {
                return []
            }
            return copying ? .copy : .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let urls = fileURLs(from: info)
            var destination = model.currentURL
            if dropOperation == .on, entries.indices.contains(row), entries[row].isDirectory {
                destination = entries[row].url
            }
            return model.handleDrop(of: urls, into: destination, copy: wantsCopy(info))
        }

        /// ⌥ forces a copy, Finder-style; sources that don't permit moving
        /// (e.g. read-only volumes) always copy.
        private func wantsCopy(_ info: NSDraggingInfo) -> Bool {
            if !info.draggingSourceOperationMask.contains(.move) { return true }
            return NSEvent.modifierFlags.contains(.option)
        }

        private func fileURLs(from info: NSDraggingInfo) -> [URL] {
            let objects = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            )
            return (objects as? [URL]) ?? []
        }
    }
}
