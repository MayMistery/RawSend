import Foundation
import Testing
@testable import RawSend

@Suite("Text highlight planning")
struct TextHighlightPlanTests {
    @Test func searchUpdateOnlyTouchesPreviousAndCurrentSearchRanges() {
        let previous = [
            SearchMatch(id: "0", range: NSRange(location: 10, length: 4), text: "test", lineNumber: 1, columnNumber: 11),
            SearchMatch(id: "1", range: NSRange(location: 30, length: 4), text: "test", lineNumber: 2, columnNumber: 4),
        ]
        let current = [
            SearchMatch(id: "0", range: NSRange(location: 10, length: 4), text: "test", lineNumber: 1, columnNumber: 11),
            SearchMatch(id: "1", range: NSRange(location: 30, length: 4), text: "test", lineNumber: 2, columnNumber: 4),
        ]

        let plan = TextHighlightPlan.make(
            previousSearchMatches: previous,
            currentSearchMatches: current,
            selectedIndex: 1,
            sourceText: String(repeating: "x", count: 10)
                + "test"
                + String(repeating: "x", count: 16)
                + "test"
        )

        #expect(plan.searchRangesToClear == previous.map(\.range))
        #expect(plan.searchRangesToApply.map(\.range) == current.map(\.range))
        #expect(plan.searchRangesToApply.map(\.isSelected) == [false, true])
        #expect(!plan.searchRangesToClear.contains(NSRange(location: 0, length: 34)))
    }

    @Test func staleMatchOutsideShortenedTextIsDiscarded() {
        let staleMatch = SearchMatch(
            id: "stale",
            range: NSRange(location: 30, length: 4),
            text: "test",
            lineNumber: 2,
            columnNumber: 4
        )

        let plan = TextHighlightPlan.make(
            previousSearchMatches: [],
            currentSearchMatches: [staleMatch],
            selectedIndex: 0,
            sourceText: "short text"
        )

        #expect(plan.searchRangesToApply.isEmpty)
        #expect(TextHighlightPlan.validRange(for: staleMatch, in: "short text") == nil)
    }

    @Test func staleMatchWhoseTextChangedIsDiscarded() {
        let staleMatch = SearchMatch(
            id: "stale",
            range: NSRange(location: 6, length: 4),
            text: "test",
            lineNumber: 1,
            columnNumber: 7
        )

        let plan = TextHighlightPlan.make(
            previousSearchMatches: [],
            currentSearchMatches: [staleMatch],
            selectedIndex: 0,
            sourceText: "value changed"
        )

        #expect(plan.searchRangesToApply.isEmpty)
        #expect(TextHighlightPlan.validRange(for: staleMatch, in: "value changed") == nil)
    }

    @Test func currentMatchCanBeHighlightedAndSelected() {
        let currentMatch = SearchMatch(
            id: "current",
            range: NSRange(location: 6, length: 4),
            text: "test",
            lineNumber: 1,
            columnNumber: 7
        )

        let plan = TextHighlightPlan.make(
            previousSearchMatches: [],
            currentSearchMatches: [currentMatch],
            selectedIndex: 0,
            sourceText: "value test"
        )

        #expect(plan.searchRangesToApply == [
            TextHighlightPlan.SearchRange(range: currentMatch.range, isSelected: true)
        ])
        #expect(TextHighlightPlan.validRange(for: currentMatch, in: "value test") == currentMatch.range)
    }
}
