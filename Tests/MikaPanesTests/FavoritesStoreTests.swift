import Foundation
import Testing
@testable import MikaPanes

@MainActor
@Suite struct FavoritesStoreTests {

    private func makeDefaults() -> (UserDefaults, cleanup: () -> Void) {
        let suite = "FavoritesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func seedsDefaultsOnFirstLaunch() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let store = FavoritesStore(defaults: defaults)
        #expect(!store.favorites.isEmpty)
        #expect(store.favorites.first?.name == "Home")
        #expect(store.contains(FileManager.default.homeDirectoryForCurrentUser))
    }

    @Test func seedsDivergentRootAsExtraFavorite() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let root = URL(fileURLWithPath: "/opt/projects", isDirectory: true)
        let store = FavoritesStore(defaults: defaults, seedRoot: root)
        #expect(store.contains(root))
    }

    @Test func doesNotReseedWhenDataExists() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let store = FavoritesStore(defaults: defaults)
        for favorite in store.favorites.dropFirst() { store.remove(favorite) }
        #expect(store.favorites.count == 1)

        let second = FavoritesStore(defaults: defaults)
        #expect(second.favorites.count == 1)
        #expect(second.favorites.first?.name == "Home")
    }

    @Test func addDeduplicatesByStandardizedURL() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let store = FavoritesStore(defaults: defaults)
        let count = store.favorites.count
        let url = URL(fileURLWithPath: "/tmp/projects", isDirectory: true)
        store.add(url)
        #expect(store.favorites.count == count + 1)
        store.add(URL(fileURLWithPath: "/tmp/projects/", isDirectory: true))
        #expect(store.favorites.count == count + 1)
    }

    @Test func removeAndPersistRoundTrip() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let store = FavoritesStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/roundtrip", isDirectory: true)
        store.add(url)
        let reloaded = FavoritesStore(defaults: defaults)
        #expect(reloaded.contains(url))

        store.remove(store.favorites.first { $0.url == url }!)
        let reloadedAgain = FavoritesStore(defaults: defaults)
        #expect(!reloadedAgain.contains(url))
    }

    @Test func moveReordersAndPersists() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let store = FavoritesStore(defaults: defaults)
        guard store.favorites.count >= 2 else { return }
        let originallySecond = store.favorites[1]
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(store.favorites.first == originallySecond)

        let reloaded = FavoritesStore(defaults: defaults)
        #expect(reloaded.favorites.first == originallySecond)
    }
}
