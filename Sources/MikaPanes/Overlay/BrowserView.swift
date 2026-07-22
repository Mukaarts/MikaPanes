import SwiftUI
import QuickLookUI

/// Finder-like main window content: a favorites sidebar, an AppKit-backed file
/// list with live fuzzy search, and a live preview pane. Keyboard handling
/// lives in the window's content view; mouse interaction is handled by the
/// table itself.
struct BrowserView: View {
    @ObservedObject var model: FileBrowserModel
    @ObservedObject var favoritesStore: FavoritesStore
    let keyHandler: (NSEvent) -> Bool

    @State private var sidebarDropTarget: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 184)
                Divider()
                listColumn
                    .frame(minWidth: 280, maxWidth: .infinity)
                Divider()
                PreviewPane(url: model.previewURL)
                    .frame(width: 320)
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 540)
    }

    // MARK: - Header (path + search)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(pathDisplay)
                .font(.system(.body, design: .rounded))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
            Spacer()
            if !model.query.isEmpty {
                scopePicker
                Text(model.query)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Search scope segments, visible while a query is active (⌘F cycles).
    private var scopePicker: some View {
        HStack(spacing: 2) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Button {
                    model.searchScope = scope
                } label: {
                    Text(scope.label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            model.searchScope == scope ? Color.accentColor.opacity(0.25) : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Favorites")
                .font(.caption).bold()
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)
            ForEach(Array(favoritesStore.favorites.enumerated()), id: \.element.id) { index, favorite in
                sidebarRow(favorite: favorite, index: index)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.25))
    }

    private func sidebarRow(favorite: Favorite, index: Int) -> some View {
        let active = model.currentURL.standardizedFileURL == favorite.url.standardizedFileURL
        let targeted = sidebarDropTarget == favorite.url
        return HStack(spacing: 8) {
            Image(systemName: favorite.systemImage)
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(favorite.name).lineLimit(1)
            Spacer(minLength: 0)
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            targeted
                ? Color.accentColor.opacity(0.35)
                : active ? Color.accentColor.opacity(0.18) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.navigate(to: favorite.url) }
        .contextMenu {
            Button("Open in New Tab") { model.openInNewTab?(favorite.url) }
            Button("Open in New Window") { model.openInNewWindow?(favorite.url) }
            Divider()
            Button("Remove from Favorites") { favoritesStore.remove(favorite) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(
                of: urls,
                into: favorite.url,
                copy: NSEvent.modifierFlags.contains(.option)
            )
        } isTargeted: { targeting in
            if targeting {
                sidebarDropTarget = favorite.url
            } else if sidebarDropTarget == favorite.url {
                sidebarDropTarget = nil
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - List

    private var listColumn: some View {
        ZStack {
            FileListView(model: model, keyHandler: keyHandler)
            if model.displayedEntries.isEmpty {
                Text(emptyPlaceholder)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
    }

    private var emptyPlaceholder: String {
        if model.query.isEmpty { return "Empty folder" }
        return model.searchStatus == .searching ? "Searching…" : "No matches"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(itemSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let search = searchStatusText {
                Text(search).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let status = model.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("↩ open · ⌫ up · Space QL · F2 rename · ⌘[/⌘] back/fwd · ⌘C/X/V clipboard")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var itemSummary: String {
        let total = "\(model.displayedEntries.count) items"
        let selected = model.selectedURLs.count
        return selected > 1 ? "\(total) · \(selected) selected" : total
    }

    private var searchStatusText: String? {
        guard model.isDeepSearchActive else { return nil }
        switch model.searchStatus {
        case .searching: return "Searching…"
        case .capped(let count): return "Showing first \(count) matches"
        default: return nil
        }
    }

    private var pathDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = model.currentURL.path
        if path == home { return "~" }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Preview pane

/// Live preview of the lead selection: an inline QuickLook render plus the
/// item's name and basic metadata.
private struct PreviewPane: View {
    let url: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let url {
                QuickLookPreview(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                metadata(for: url)
            } else {
                Spacer()
                Text("No selection").foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func metadata(for url: URL) -> some View {
        let values = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey
        ])
        let isDir = values?.isDirectory ?? false
        return VStack(alignment: .leading, spacing: 4) {
            Text(url.lastPathComponent).font(.callout).bold().lineLimit(2)
            if let type = values?.localizedTypeDescription { metaRow("Kind", type) }
            if !isDir, let size = values?.fileSize {
                metaRow("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            if let date = values?.contentModificationDate {
                metaRow("Modified", date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

/// Bridges `QLPreviewView` into SwiftUI for an inline, Finder-style preview.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url.map { $0 as NSURL }
    }
}
