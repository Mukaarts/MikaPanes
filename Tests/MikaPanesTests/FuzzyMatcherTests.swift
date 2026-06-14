import Testing
@testable import MikaPanes

@Suite struct FuzzyMatcherTests {

    @Test func emptyQueryMatchesEverythingNeutrally() {
        #expect(FuzzyMatcher.score("anything.txt", query: "") == 0)
    }

    @Test func subsequenceMatches() {
        #expect(FuzzyMatcher.score("README.md", query: "rdm") != nil)
        #expect(FuzzyMatcher.score("MikaPanes", query: "mkp") != nil)
    }

    @Test func nonSubsequenceFails() {
        #expect(FuzzyMatcher.score("README", query: "xyz") == nil)
        #expect(FuzzyMatcher.score("abc", query: "abcd") == nil)
    }

    @Test func caseInsensitive() {
        #expect(FuzzyMatcher.score("Downloads", query: "DOWN") != nil)
        #expect(FuzzyMatcher.score("Downloads", query: "down") != nil)
    }

    @Test func contiguousPrefixScoresHigherThanScattered() throws {
        let prefix = try #require(FuzzyMatcher.score("report.pdf", query: "rep"))
        let scattered = try #require(FuzzyMatcher.score("recipe-prep.pdf", query: "rep"))
        #expect(prefix > scattered)
    }

    @Test func wordBoundaryBonus() throws {
        // "fb" should rank "foo-bar" (boundary match on 'b') above "fabric".
        let boundary = try #require(FuzzyMatcher.score("foo-bar", query: "fb"))
        let inline = try #require(FuzzyMatcher.score("fabric", query: "fb"))
        #expect(boundary > inline)
    }
}
