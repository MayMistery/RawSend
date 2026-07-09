import Foundation
import Testing
@testable import RawSend

@Suite("HTML syntax highlighter")
struct HTMLSyntaxHighlighterTests {
    @Test func tokenRangesClassifyHTMLBodyTokens() {
        let html = #"<!doctype html><html lang="en"><body><h1 class='title'>RawSend &amp; HTML</h1><!-- ok --></body></html>"#

        let tokens = HTMLSyntaxHighlighter.tokenRanges(in: html)
        let source = html as NSString
        let values = tokens.map { "\($0.kind.rawValue):\(source.substring(with: $0.range))" }

        #expect(values.contains("tag:doctype"))
        #expect(values.contains("tag:html"))
        #expect(values.contains("attributeName:lang"))
        #expect(values.contains(#"attributeValue:"en""#))
        #expect(values.contains("tag:h1"))
        #expect(values.contains("attributeName:class"))
        #expect(values.contains("attributeValue:'title'"))
        #expect(values.contains("entity:&amp;"))
        #expect(values.contains("comment:<!-- ok -->"))
    }

    @Test func httpTextSyntaxDetectsHTMLPreviewBody() throws {
        let text = "HTTP/1.1 200 OK\nContent-Type: text/html\n\n<html><body>Hello</body></html>"

        let preview = try #require(HTTPTextSyntax.htmlPreviewBody(in: text))

        #expect(preview == "<html><body>Hello</body></html>")
    }
}
