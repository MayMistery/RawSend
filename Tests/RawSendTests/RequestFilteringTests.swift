import Foundation
import Testing
@testable import RawSend

@Suite("Request filtering")
struct RequestFilteringTests {
    @Test func filteredRequestDropsManualAndKeywordStruckHeaders() throws {
        let request = HTTPRequest(
            method: "GET",
            host: "example.com",
            path: "/",
            headers: [
                ("X-Manual", "drop"),
                ("Authorization", "Bearer secret"),
                ("Accept", "*/*"),
            ]
        )
        let manualID = HeaderInspector.headerID(index: 0, name: "X-Manual", value: "drop")

        let filtered = HeaderInspector.filteredRequest(
            request,
            manuallyStruckIDs: [manualID],
            keywords: ["auth"],
            redactMatchingKeywords: true
        )

        #expect(filtered.headers.map { "\($0.0): \($0.1)" } == ["Accept: */*"])
        #expect(filtered.method == request.method)
        #expect(filtered.host == request.host)
        #expect(filtered.path == request.path)
    }

    @Test func filteredRequestKeepsKeywordHeadersWhenKeywordRedactionIsDisabled() {
        let request = HTTPRequest(
            method: "GET",
            host: "example.com",
            path: "/",
            headers: [
                ("Authorization", "Bearer secret"),
                ("Accept", "*/*"),
            ]
        )

        let filtered = HeaderInspector.filteredRequest(
            request,
            manuallyStruckIDs: [],
            keywords: ["auth"],
            redactMatchingKeywords: false
        )

        #expect(filtered.headers.map { "\($0.0): \($0.1)" } == [
            "Authorization: Bearer secret",
            "Accept: */*",
        ])
    }

    @Test func rawToCurlOmitsStruckHeaders() throws {
        let raw = """
        GET / HTTP/1.1
        Host: example.com
        Authorization: Bearer secret
        X-Trace: keep
        Cookie: sid=123

        """

        let curl = try #require(CurlConverter.rawToCurl(
            raw,
            manuallyStruckIDs: [],
            redactionKeywords: ["auth", "cookie"],
            redactMatchingKeywords: true
        ))

        #expect(!curl.contains("Authorization"))
        #expect(!curl.contains("Cookie"))
        #expect(curl.contains("X-Trace: keep"))
    }
}
