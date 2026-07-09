import Foundation

struct TextHighlightPlan {
    struct SearchRange: Equatable {
        let range: NSRange
        let isSelected: Bool
    }

    let searchRangesToClear: [NSRange]
    let searchRangesToApply: [SearchRange]

    static func make(
        previousSearchMatches: [SearchMatch],
        currentSearchMatches: [SearchMatch],
        selectedIndex: Int?,
        fullTextRange: NSRange
    ) -> TextHighlightPlan {
        let clearRanges = previousSearchMatches
            .map(\.range)
            .filter { NSIntersectionRange($0, fullTextRange).length == $0.length }

        let applyRanges = currentSearchMatches.enumerated().compactMap { index, match -> SearchRange? in
            guard NSIntersectionRange(match.range, fullTextRange).length == match.range.length else { return nil }
            return SearchRange(range: match.range, isSelected: index == selectedIndex)
        }

        return TextHighlightPlan(searchRangesToClear: clearRanges, searchRangesToApply: applyRanges)
    }
}
