import Foundation
import Testing
@testable import RawSend

@Suite("Search engine")
struct SearchEngineTests {
    @Test func findsCaseInsensitiveMatchesWithRanges() {
        let matches = SearchEngine.matches(in: "Token token TOKEN", query: "token")

        #expect(matches.map(\.text) == ["Token", "token", "TOKEN"])
        #expect(matches.map(\.range.location) == [0, 6, 12])
        #expect(matches.map(\.range.length) == [5, 5, 5])
    }

    @Test func emptyOrWhitespaceQueryReturnsNoMatches() {
        #expect(SearchEngine.matches(in: "abc", query: "").isEmpty)
        #expect(SearchEngine.matches(in: "abc", query: "  ").isEmpty)
    }

    @Test func nextAndPreviousMatchWrapAround() {
        let matches = SearchEngine.matches(in: "one two one", query: "one")

        #expect(SearchEngine.nextIndex(after: nil, matchCount: matches.count) == 0)
        #expect(SearchEngine.nextIndex(after: 0, matchCount: matches.count) == 1)
        #expect(SearchEngine.nextIndex(after: 1, matchCount: matches.count) == 0)
        #expect(SearchEngine.previousIndex(before: nil, matchCount: matches.count) == 1)
        #expect(SearchEngine.previousIndex(before: 1, matchCount: matches.count) == 0)
        #expect(SearchEngine.previousIndex(before: 0, matchCount: matches.count) == 1)
    }

    @Test func matchesIncludeLineAndColumnForJumping() {
        let text = "alpha\nbeta token\ngamma token"

        let matches = SearchEngine.matches(in: text, query: "token")

        #expect(matches.map(\.lineNumber) == [2, 3])
        #expect(matches.map(\.columnNumber) == [6, 7])
    }

    @Test func matchesIncludeLineAndColumnForCRLFHTTPText() {
        let text = "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n{\"token\":true}"

        let matches = SearchEngine.matches(in: text, query: "token")

        #expect(matches.first?.lineNumber == 4)
        #expect(matches.first?.columnNumber == 3)
    }

    @Test func largeTextSearchStaysWithinInteractiveBudget() {
        let chunk = String(repeating: "alpha beta gamma delta\n", count: 5_000)
        let text = chunk + "needle\n" + chunk + "needle\n"

        let started = Date()
        let matches = SearchEngine.matches(in: text, query: "needle")
        let elapsed = Date().timeIntervalSince(started)

        #expect(matches.count == 2)
        #expect(elapsed < 0.2, "search took \(elapsed)s")
    }
}
