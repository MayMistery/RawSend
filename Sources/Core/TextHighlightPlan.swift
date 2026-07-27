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
        sourceText: String
    ) -> TextHighlightPlan {
        let source = sourceText as NSString
        let fullTextRange = NSRange(location: 0, length: source.length)
        let clearRanges = previousSearchMatches
            .map(\.range)
            .filter { contains($0, in: fullTextRange) }

        let applyRanges = currentSearchMatches.enumerated().compactMap { index, match -> SearchRange? in
            guard validRange(for: match, in: source) != nil else { return nil }
            return SearchRange(range: match.range, isSelected: index == selectedIndex)
        }

        return TextHighlightPlan(searchRangesToClear: clearRanges, searchRangesToApply: applyRanges)
    }

    static func validRange(for match: SearchMatch, in sourceText: String) -> NSRange? {
        let source = sourceText as NSString
        return validRange(for: match, in: source)
    }

    private static func validRange(for match: SearchMatch, in source: NSString) -> NSRange? {
        let fullTextRange = NSRange(location: 0, length: source.length)
        guard contains(match.range, in: fullTextRange),
              source.substring(with: match.range) == match.text else {
            return nil
        }
        return match.range
    }

    private static func contains(_ range: NSRange, in fullTextRange: NSRange) -> Bool {
        guard range.location != NSNotFound,
              range.location >= fullTextRange.location,
              range.length >= 0 else {
            return false
        }

        let relativeLocation = range.location - fullTextRange.location
        return relativeLocation <= fullTextRange.length
            && range.length <= fullTextRange.length - relativeLocation
    }
}
