import SwiftUI
import QuickLookUI

/// Finder-like main window content: a favorites sidebar, a file list with live
/// fuzzy search, and a live preview pane. Keyboard handling lives in the window's
/// content view; mouse clicks are a convenience.
struct BrowserView: View {
    @ObservedObject var model: FileBrowserModel

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
                    .id(model.previewURL)
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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Favorites")
                .font(.caption).bold()
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)
            ForEach(Array(model.favorites.enumerated()), id: \.element.id) { index, favorite in
                let active = model.currentURL.standardizedFileURL == favorite.url.standardizedFileURL
                HStack(spacing: 8) {
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
                .background(active ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { model.navigate(to: favorite.url) }
                .padding(.horizontal, 6)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.25))
    }

    // MARK: - List

    private var listColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let entries = model.filteredEntries
                    if entries.isEmpty {
                        Text(model.query.isEmpty ? "Empty folder" : "No matches")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(for: entry, selected: index == model.selectionIndex)
                            .id(index)
                            .onTapGesture(count: 2) {
                                model.select(entry)
                                model.activateSelection()
                            }
                            .onTapGesture { model.select(entry) }
                    }
                }
            }
            .onChange(of: model.selectionIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func row(for entry: FileBrowserModel.Entry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 18)
            Text(entry.name).lineLimit(1)
            Spacer()
            if entry.isDirectory {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.filteredEntries.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let status = model.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("↩ open · ⌫ up · Space QL · ⌘R reveal · ⌘⌫ trash · ⌘C/⌘X/⌘V")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
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

/// Live preview of the highlighted item: an inline QuickLook render plus the
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
