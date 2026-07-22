import SwiftUI
import AppKit

/// Content of the Settings window: the start folder for new windows and the
/// shared favorites editor (add/remove/reorder — reordering lives here, not in
/// the sidebar, whose drag targets are reserved for moving files).
struct PreferencesView: View {
    @ObservedObject var favoritesStore: FavoritesStore
    let settings: SettingsStore

    @State private var browserRoot: URL
    @State private var selectedFavoriteIDs: Set<URL> = []

    init(favoritesStore: FavoritesStore, settings: SettingsStore) {
        self.favoritesStore = favoritesStore
        self.settings = settings
        _browserRoot = State(initialValue: settings.browserRoot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            generalSection
            Divider()
            favoritesSection
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("General").font(.headline)
            HStack(spacing: 8) {
                Text("Start Folder")
                Text(abbreviated(browserRoot))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose…") { chooseStartFolder() }
            }
            Text("Applies to new windows.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func chooseStartFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = browserRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.browserRoot = url
        browserRoot = url
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favorites").font(.headline)
            List(selection: $selectedFavoriteIDs) {
                ForEach(favoritesStore.favorites) { favorite in
                    HStack(spacing: 8) {
                        Image(systemName: favorite.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(favorite.name)
                        Spacer(minLength: 8)
                        Text(abbreviated(favorite.url))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .tag(favorite.id)
                }
                .onMove { source, destination in
                    favoritesStore.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                Button {
                    addFavoriteViaPanel()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    removeSelectedFavorites()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedFavoriteIDs.isEmpty)
                Spacer()
                Text("Drag to reorder · ⌘1–⌘9 follow this order")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func addFavoriteViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { favoritesStore.add(url) }
    }

    private func removeSelectedFavorites() {
        let doomed = favoritesStore.favorites.filter { selectedFavoriteIDs.contains($0.id) }
        for favorite in doomed { favoritesStore.remove(favorite) }
        selectedFavoriteIDs = []
    }

    private func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path == home { return "~" }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
