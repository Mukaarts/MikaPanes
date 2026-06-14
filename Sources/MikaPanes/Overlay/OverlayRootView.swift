import SwiftUI

/// Presentational overlay UI. All keyboard handling happens in `OverlayPanel`;
/// this view only reflects `FileBrowserModel` state.
struct OverlayRootView: View {
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

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
    }

    @ViewBuilder
    private var content: some View {
        switch model.sourceMode {
        case .ownBrowser:
            browserList
        case .finderSelection:
            finderList
        }
    }

    private var browserList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let entries = model.filteredEntries
                    if entries.isEmpty {
                        emptyState("Nothing here")
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(for: entry, selected: index == model.selectionIndex)
                            .id(index)
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
            Text(entry.name)
                .lineLimit(1)
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

    private var finderList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.finderSelection.isEmpty {
                    emptyState("No Finder selection")
                }
                ForEach(model.finderSelection, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(url.deletingLastPathComponent().lastPathComponent)
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(model.sourceMode.label, systemImage: model.sourceMode == .ownBrowser ? "list.bullet" : "macwindow")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let status = model.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("⇥ source · Space QL · ⌘R reveal · ⌘⌫ trash · ⌘C copy · ⌘M move")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var pathDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = model.currentURL.path
        if path == home { return "~" }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
