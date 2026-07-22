import Foundation
import Testing
@testable import MikaPanes

@Suite struct NavigationHistoryTests {

    private func location(_ path: String, selecting: [String] = []) -> NavigationHistory.Location {
        NavigationHistory.Location(
            url: URL(fileURLWithPath: path, isDirectory: true),
            selectedURLs: Set(selecting.map { URL(fileURLWithPath: $0) })
        )
    }

    @Test func emptyHistoryHasNothingToNavigate() {
        var history = NavigationHistory()
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
        #expect(history.goBack(from: location("/Users")) == nil)
        #expect(history.goForward(from: location("/Users")) == nil)
        // Failed navigation must not mutate the stacks.
        #expect(history == NavigationHistory())
    }

    @Test func recordNavigationEnablesBackOnly() {
        var history = NavigationHistory()
        history.recordNavigation(from: location("/Users"))
        #expect(history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func backForwardRoundtripRestoresSelection() throws {
        var history = NavigationHistory()
        let home = location("/Users/mika", selecting: ["/Users/mika/Documents"])
        let documents = location("/Users/mika/Documents", selecting: ["/Users/mika/Documents/todo.txt"])

        history.recordNavigation(from: home)

        // Mutating calls cannot appear inside #require's autoclosure.
        let backResult = history.goBack(from: documents)
        let back = try #require(backResult)
        #expect(back == home)
        #expect(back.selectedURLs == [URL(fileURLWithPath: "/Users/mika/Documents")])
        #expect(!history.canGoBack)
        #expect(history.canGoForward)

        let forwardResult = history.goForward(from: back)
        let forward = try #require(forwardResult)
        #expect(forward == documents)
        #expect(forward.selectedURLs == [URL(fileURLWithPath: "/Users/mika/Documents/todo.txt")])
        #expect(history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func recordNavigationClearsForwardStack() {
        var history = NavigationHistory()
        let a = location("/a")
        let b = location("/b")

        history.recordNavigation(from: a)
        #expect(history.goBack(from: b) == a)
        #expect(history.canGoForward)

        // Branching off after going back discards the forward path, like Finder.
        history.recordNavigation(from: a)
        #expect(!history.canGoForward)
        #expect(history.forwardStack.isEmpty)
        #expect(history.backStack == [a])
    }

    @Test func multipleBackStepsPopInLIFOOrder() {
        var history = NavigationHistory()
        let root = location("/")
        let users = location("/Users")
        let home = location("/Users/mika")
        let current = location("/Users/mika/Desktop")

        history.recordNavigation(from: root)
        history.recordNavigation(from: users)
        history.recordNavigation(from: home)

        #expect(history.goBack(from: current) == home)
        #expect(history.goBack(from: home) == users)
        #expect(history.goBack(from: users) == root)
        #expect(!history.canGoBack)
        #expect(history.forwardStack == [current, home, users])
    }

    @Test func multipleForwardStepsReplayInReverseOrder() {
        var history = NavigationHistory()
        let root = location("/")
        let users = location("/Users")
        let home = location("/Users/mika")

        history.recordNavigation(from: root)
        history.recordNavigation(from: users)
        _ = history.goBack(from: home)
        _ = history.goBack(from: users)

        // Walking forward re-visits locations in original navigation order.
        #expect(history.goForward(from: root) == users)
        #expect(history.goForward(from: users) == home)
        #expect(!history.canGoForward)
        #expect(history.backStack == [root, users])
    }
}
