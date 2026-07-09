import AppKit

enum TextViewNavigator {
    static func center(_ range: NSRange, in textView: NSTextView) {
        guard range.location != NSNotFound, range.location < (textView.string as NSString).length else { return }
        textView.scrollRangeToVisible(range)

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let inset = textView.textContainerInset
        let targetMidY = glyphRect.midY + inset.height
        let visibleHeight = scrollView.contentView.bounds.height
        let maxY = max(0, textView.bounds.height - visibleHeight)
        let nextY = min(max(0, targetMidY - visibleHeight / 2), maxY)

        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: nextY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
