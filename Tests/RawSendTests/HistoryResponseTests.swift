import Foundation
import Testing
@testable import RawSend

@Suite("History responses")
struct HistoryResponseTests {
    @Test func historyItemStoresHTTPAndHTTPSResponses() throws {
        let request = HTTPRequest(method: "GET", host: "example.com", path: "/status", headers: [])
        var item = HistoryItem(rawText: "GET /status HTTP/1.1\r\nHost: example.com\r\n\r\n", request: request, environmentName: "Default")
        let http = HTTPResponse(urlResponse: nil, data: Data(#"{"ok":true}"#.utf8), elapsed: 0.12)
        let https = HTTPResponse(urlResponse: nil, data: Data(#"{"secure":true}"#.utf8), elapsed: 0.18)

        item.updateResponses(http: http, https: https)
        let storedHTTP = try #require(item.httpResponse)
        let storedHTTPS = try #require(item.httpsResponse)

        #expect(storedHTTP.fullText == http.fullResponseText)
        #expect(storedHTTPS.fullText == https.fullResponseText)
        #expect(HTTPResponse.archived(storedHTTP).fullResponseText == http.fullResponseText)
        #expect(HTTPResponse.archived(storedHTTPS).fullResponseText == https.fullResponseText)
    }
}
