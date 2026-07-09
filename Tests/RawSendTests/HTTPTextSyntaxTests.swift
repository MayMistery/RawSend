import Foundation
import Testing
@testable import RawSend

@Suite("HTTP text syntax")
struct HTTPTextSyntaxTests {
    @Test func identifiesStatusHeaderAndJSONRangesInFullResponseText() throws {
        let text = "HTTP/1.1 200 OK\nServer: unit\nContent-Type: application/json\n\n{\"ok\":true,\"count\":2}"
        let source = text as NSString

        let firstToken = try #require(HTTPTextSyntax.firstTokenRange(in: text))
        let statusCode = try #require(HTTPTextSyntax.statusCodeRange(in: text))
        let headerNames = HTTPTextSyntax.headerNameRanges(in: text)
        let jsonTokens = HTTPTextSyntax.jsonTokens(in: text)

        #expect(source.substring(with: firstToken) == "HTTP/1.1")
        #expect(source.substring(with: statusCode.range) == "200")
        #expect(statusCode.code == 200)
        #expect(headerNames.map { source.substring(with: $0) } == ["Server", "Content-Type"])
        #expect(jsonTokens.contains { $0.kind == .key && source.substring(with: $0.range) == #""ok""# })
        #expect(jsonTokens.contains { $0.kind == .number && source.substring(with: $0.range) == "2" })
    }
}
