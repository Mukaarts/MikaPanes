import Foundation

/// Finder-style back/forward history for the file browser (⌘[ / ⌘]).
/// Pure value type; the model owns the current location and passes it in so
/// history entries capture the selection at the moment of leaving.
struct NavigationHistory: Equatable {

    /// A visited directory together with the selection it had when left.
    struct Location: Equatable {
        var url: URL
        var selectedURLs: Set<URL>
    }

    private(set) var backStack: [Location] = []
    private(set) var forwardStack: [Location] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Call on every fresh navigation (descend, favorite jump, parent) with the
    /// location being left. Invalidates the forward stack, like Finder.
    /// Reloads must not call this.
    mutating func recordNavigation(from current: Location) {
        backStack.append(current)
        forwardStack.removeAll()
    }

    /// Returns the previous location to restore, or `nil` if there is none.
    mutating func goBack(from current: Location) -> Location? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        return previous
    }

    /// Returns the next location to restore, or `nil` if there is none.
    mutating func goForward(from current: Location) -> Location? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        return next
    }
}
