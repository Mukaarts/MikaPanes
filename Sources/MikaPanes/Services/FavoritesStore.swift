import Foundation

/// A sidebar favorite. Codable for JSON persistence in UserDefaults.
struct Favorite: Identifiable, Hashable, Codable {
    let name: String
    let systemImage: String
    let url: URL
    var id: URL { url }
}

/// App-wide, persistent favorites shared by every browser window and the
/// preferences editor. Mutations publish immediately, so all sidebars stay in
/// sync; persistence is a JSON blob in UserDefaults.
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var favorites: [Favorite] = []

    private let defaults: UserDefaults
    private static let key = "favorites.items"

    /// Seeds the previous hard-coded defaults on first launch (missing key).
    init(defaults: UserDefaults = .standard, seedRoot: URL? = nil) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = stored
        } else {
            favorites = Self.defaultFavorites(root: seedRoot)
            persist()
        }
    }

    func contains(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        return favorites.contains { $0.url.standardizedFileURL == target }
    }

    func add(_ url: URL) {
        guard !contains(url) else { return }
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        favorites.append(Favorite(name: name, systemImage: "folder", url: url))
        persist()
    }

    func remove(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func defaultFavorites(root: URL?) -> [Favorite] {
        let fm = FileManager.default
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? {
            fm.urls(for: d, in: .userDomainMask).first
        }
        var favorites: [Favorite] = [
            Favorite(name: "Home", systemImage: "house", url: fm.homeDirectoryForCurrentUser)
        ]
        if let url = dir(.desktopDirectory) {
            favorites.append(Favorite(name: "Desktop", systemImage: "menubar.dock.rectangle", url: url))
        }
        if let url = dir(.documentDirectory) {
            favorites.append(Favorite(name: "Documents", systemImage: "doc", url: url))
        }
        if let url = dir(.downloadsDirectory) {
            favorites.append(Favorite(name: "Downloads", systemImage: "arrow.down.circle", url: url))
        }
        if let root, !favorites.contains(where: { $0.url.standardizedFileURL == root.standardizedFileURL }) {
            favorites.append(Favorite(name: root.lastPathComponent, systemImage: "star", url: root))
        }
        return favorites
    }
}
