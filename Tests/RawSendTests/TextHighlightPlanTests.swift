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
            fullTextRange: NSRange(location: 0, length: 1_000)
        )

        #expect(plan.searchRangesToClear == previous.map(\.range))
        #expect(plan.searchRangesToApply.map(\.range) == current.map(\.range))
        #expect(plan.searchRangesToApply.map(\.isSelected) == [false, true])
        #expect(!plan.searchRangesToClear.contains(NSRange(location: 0, length: 1_000)))
    }
}
