import SwiftUI
import AppKit

struct ResponseTextView: NSViewRepresentable {
    let text: String
    let lineIndex: TextLineIndex
    let searchText: String
    let searchMatches: [SearchMatch]
    let selectedSearchMatchIndex: Int?
    var riskHighlights: [RiskHighlight] = []
    var markActive: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ActiveTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.font = Self.codeFont
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.string = text
        textView.markActive = markActive

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.apply(
            text: text,
            lineIndex: lineIndex,
            searchText: searchText,
            searchMatches: searchMatches,
            selectedIndex: selectedSearchMatchIndex,
            riskHighlights: riskHighlights
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(
            text: text,
            lineIndex: lineIndex,
            searchText: searchText,
            searchMatches: searchMatches,
            selectedIndex: selectedSearchMatchIndex,
            riskHighlights: riskHighlights
        )
        if let textView = nsView.documentView as? ActiveTextView {
            textView.markActive = markActive
        }
    }

    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private final class ActiveTextView: NSTextView {
        var markActive: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            markActive()
            super.mouseDown(with: event)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        private var appliedText: String = ""
        private var appliedSearchMatches: [SearchMatch] = []
        private var appliedRiskRanges: [NSRange] = []
        private var appliedSelectedSearchID: String?
        private var cachedJSONText: String = ""
        private var cachedJSONTokens: [JSONSyntaxToken] = []
        private var cachedHTMLText: String = ""
        private var cachedHTMLTokens: [HTMLSyntaxToken] = []

        func apply(
            text: String,
            lineIndex: TextLineIndex,
            searchText: String,
            searchMatches: [SearchMatch],
            selectedIndex: Int?,
            riskHighlights: [RiskHighlight]
        ) {
            let started = Date()
            guard let textView else { return }
            let textChanged = appliedText != text || textView.string != text

            if textChanged {
                textView.string = text
                appliedText = text
                appliedSearchMatches = []
                appliedRiskRanges = []
                appliedSelectedSearchID = nil
                applyBaseAttributes(to: textView, text: text)
            }

            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            applyRiskHighlights(riskHighlights, lineIndex: lineIndex, fullRange: fullRange, textView: textView)
            applySearchHighlights(
                matches: searchMatches,
                selectedIndex: selectedIndex,
                textView: textView
            )
            scrollToSelectedMatchIfNeeded(
                matches: searchMatches,
                selectedIndex: selectedIndex,
                textView: textView
            )

            PerformanceLogStore.appendIfSlow(
                operation: "highlight",
                source: "response",
                elapsed: Date().timeIntervalSince(started),
                textLength: fullRange.length,
                queryLength: (searchText as NSString).length,
                matchCount: searchMatches.count
            )
        }

        private func applyBaseAttributes(to textView: NSTextView, text: String) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            storage.beginEditing()
            storage.setAttributes([
                .font: ResponseTextView.codeFont,
                .foregroundColor: NSColor.textColor,
            ], range: fullRange)

            if let firstTokenRange = HTTPTextSyntax.firstTokenRange(in: text) {
                storage.addAttributes([
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                ], range: firstTokenRange)
            }

            if let status = HTTPTextSyntax.statusCodeRange(in: text) {
                storage.addAttributes([
                    .foregroundColor: Self.statusColor(for: status.code),
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                ], range: status.range)
            }

            for range in HTTPTextSyntax.headerNameRanges(in: text) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
            }

            for token in jsonTokens(in: text) {
                storage.addAttributes(Self.jsonAttributes(for: token.kind), range: token.range)
            }

            for token in htmlTokens(in: text) {
                storage.addAttributes(Self.htmlAttributes(for: token.kind), range: token.range)
            }

            storage.endEditing()
        }

        private func applyRiskHighlights(
            _ riskHighlights: [RiskHighlight],
            lineIndex: TextLineIndex,
            fullRange: NSRange,
            textView: NSTextView
        ) {
            guard let layoutManager = textView.layoutManager else { return }
            for range in appliedRiskRanges {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            }

            let ranges: [(range: NSRange, severity: String)] = riskHighlights.compactMap { highlight in
                guard let line = lineIndex.line(at: highlight.line),
                      NSIntersectionRange(line.lineRange, fullRange).length == line.lineRange.length else { return nil }
                return (line.lineRange, highlight.severity)
            }

            for item in ranges {
                layoutManager.addTemporaryAttributes([
                    .backgroundColor: Self.backgroundColor(for: item.severity),
                ], forCharacterRange: item.range)
            }
            appliedRiskRanges = ranges.map(\.range)
        }

        private func applySearchHighlights(
            matches: [SearchMatch],
            selectedIndex: Int?,
            textView: NSTextView
        ) {
            guard let layoutManager = textView.layoutManager else { return }
            let plan = TextHighlightPlan.make(
                previousSearchMatches: appliedSearchMatches,
                currentSearchMatches: matches,
                selectedIndex: selectedIndex,
                sourceText: textView.string
            )

            for range in plan.searchRangesToClear {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            }
            for item in plan.searchRangesToApply {
                layoutManager.addTemporaryAttributes([
                    .backgroundColor: item.isSelected
                        ? NSColor.systemYellow.withAlphaComponent(0.65)
                        : NSColor.systemYellow.withAlphaComponent(0.28),
                ], forCharacterRange: item.range)
            }
            appliedSearchMatches = matches
        }

        private func scrollToSelectedMatchIfNeeded(
            matches: [SearchMatch],
            selectedIndex: Int?,
            textView: NSTextView
        ) {
            guard let selectedIndex,
                  matches.indices.contains(selectedIndex) else {
                appliedSelectedSearchID = nil
                return
            }

            let match = matches[selectedIndex]
            guard let validRange = TextHighlightPlan.validRange(for: match, in: textView.string),
                  appliedSelectedSearchID != match.id else { return }
            appliedSelectedSearchID = match.id
            textView.setSelectedRange(validRange)
            TextViewNavigator.center(validRange, in: textView)
        }

        private func jsonTokens(in text: String) -> [JSONSyntaxToken] {
            if text == cachedJSONText {
                return cachedJSONTokens
            }

            cachedJSONText = text
            cachedJSONTokens = HTTPTextSyntax.jsonTokens(in: text, maximumTokens: 20_000)
            return cachedJSONTokens
        }

        private func htmlTokens(in text: String) -> [HTMLSyntaxToken] {
            if text == cachedHTMLText {
                return cachedHTMLTokens
            }

            cachedHTMLText = text
            cachedHTMLTokens = HTTPTextSyntax.htmlTokens(in: text, maximumTokens: 20_000)
            return cachedHTMLTokens
        }

        private static func statusColor(for code: Int) -> NSColor {
            switch code {
            case 200..<300:
                return NSColor.systemGreen
            case 300..<400:
                return NSColor.systemBlue
            case 400..<500:
                return NSColor.systemOrange
            case 500..<600:
                return NSColor.systemRed
            default:
                return NSColor.secondaryLabelColor
            }
        }

        private static func backgroundColor(for severity: String) -> NSColor {
            switch severity.lowercased() {
            case "high":
                return NSColor.systemRed.withAlphaComponent(0.18)
            case "low":
                return NSColor.systemBlue.withAlphaComponent(0.12)
            default:
                return NSColor.systemOrange.withAlphaComponent(0.16)
            }
        }

        private static func jsonAttributes(for kind: JSONSyntaxToken.Kind) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .key:
                return [
                    .foregroundColor: NSColor.systemPurple,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                ]
            case .string:
                return [.foregroundColor: NSColor.systemGreen]
            case .number:
                return [.foregroundColor: NSColor.systemBlue]
            case .literal:
                return [.foregroundColor: NSColor.systemOrange]
            case .punctuation:
                return [.foregroundColor: NSColor.secondaryLabelColor]
            }
        }

        private static func htmlAttributes(for kind: HTMLSyntaxToken.Kind) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .tag:
                return [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                ]
            case .attributeName:
                return [.foregroundColor: NSColor.systemPurple]
            case .attributeValue:
                return [.foregroundColor: NSColor.systemGreen]
            case .comment:
                return [.foregroundColor: NSColor.secondaryLabelColor]
            case .entity:
                return [.foregroundColor: NSColor.systemOrange]
            case .punctuation:
                return [.foregroundColor: NSColor.secondaryLabelColor]
            }
        }
    }
}
