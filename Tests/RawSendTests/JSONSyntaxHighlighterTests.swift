import Foundation
import Testing
@testable import RawSend

@Suite("JSON syntax highlighter")
struct JSONSyntaxHighlighterTests {
    @Test func bodyRangeFindsHTTPMessageBody() throws {
        let raw = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n{\"ok\":true}"

        let range = try #require(HTTPMessageRanges.bodyRange(in: raw))

        #expect((raw as NSString).substring(with: range) == #"{"ok":true}"#)
    }

    @Test func jsonTokenRangesClassifyCommonJSONTokens() {
        let json = #"{"name":"rawsend","count":2,"ok":true,"items":[null]}"#

        let tokens = JSONSyntaxHighlighter.tokenRanges(in: json)
        let values = tokens.map { token in
            "\(token.kind.rawValue):\((json as NSString).substring(with: token.range))"
        }

        #expect(values.contains(#"key:"name""#))
        #expect(values.contains(#"string:"rawsend""#))
        #expect(values.contains("number:2"))
        #expect(values.contains("literal:true"))
        #expect(values.contains("literal:null"))
        #expect(values.contains("punctuation:{"))
        #expect(values.contains("punctuation:}"))
    }
}
