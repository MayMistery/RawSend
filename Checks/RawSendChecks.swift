import Darwin
import Foundation

@main
struct RawSendChecks {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        let importantLines = HeaderInspector.makeHeaderLines(from: [
            ("host", "example.com"),
            ("X-Env", "test"),
            ("X-Service", "rawsend"),
            ("X-Lane", "local"),
        ], manuallyStruckIDs: [], keywords: [])
        let important = HeaderInspector.importantHeaders(from: importantLines)
        expect(important.isEmpty, "important headers should have no built-in header names")
        let customImportant = HeaderInspector.importantHeaders(from: importantLines, names: ["x-service", "x-env"])
        expect(customImportant.map(\.name) == ["X-Service", "X-Env"], "important headers should support a configurable ordered name list")

        let sensitive = HeaderInspector.makeHeaderLines(from: [
            ("Authorization", "Bearer abc"),
            ("X-Trace", "contains-token-value"),
            ("Accept", "application/json"),
            ("Cookie", "sid=123"),
        ], manuallyStruckIDs: [], keywords: ["token", "AUTH", "cookie"])
        expect(sensitive.map(\.isStruck) == [true, true, false, true], "keyword redaction should match header names and values")

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
        expect(filtered.headers.map { "\($0.0): \($0.1)" } == ["Accept: */*"], "filtered request should omit manual and keyword-struck headers")

        let bodyRequest = """
        POST /submit HTTP/1.1\r
        Host: example.com\r
        Content-Type: application/json\r
        \r
        {"name":"rawsend"}
        """
        expect(RequestParser.parse(bodyRequest)?.body == #"{"name":"rawsend"}"#, "request parser should preserve body after CRLF header separator")
        expect(RequestParser.bodyByteCount(bodyRequest) == 18, "body byte count should count the parsed request body")

        let queryRequest = HTTPRequest(
            method: "GET",
            host: "example.com",
            path: "/admin?appId=13&auth_token=secret&flight_id=5242837#frag",
            headers: []
        )
        let queryParams = QueryParameterInspector.makeParameters(
            from: queryRequest.path,
            manuallyStruckIDs: [],
            keywords: ["auth"]
        )
        expect(queryParams.map(\.isStruck) == [false, true, false], "query params should be struck by keyword")
        let queryFiltered = QueryParameterInspector.filteredRequest(
            queryRequest,
            manuallyStruckIDs: [],
            keywords: ["auth"],
            redactMatchingKeywords: true
        )
        expect(queryFiltered.path == "/admin?appId=13&flight_id=5242837#frag", "filtered query params should be omitted from the sent path")
        let flightID = QueryParameterInspector.parameterID(index: 2, name: "flight_id")
        let manualQueryFiltered = QueryParameterInspector.filteredRequest(
            queryRequest,
            manuallyStruckIDs: [flightID],
            keywords: [],
            redactMatchingKeywords: false
        )
        expect(manualQueryFiltered.path == "/admin?appId=13&auth_token=secret#frag", "manually struck query params should be omitted from the sent path")

        let rawRequest = """
        GET / HTTP/1.1
        Host: example.com
        Authorization: Bearer secret

        body
        """
        let authLocation = (rawRequest as NSString).range(of: "Bearer").location
        let inlineHeader = HeaderInspector.headerLine(in: rawRequest, atUTF16Location: authLocation)
        expect(inlineHeader?.name == "Authorization", "inline header lookup should find the header under the cursor")
        expect(inlineHeader?.id == HeaderInspector.headerID(index: 1, name: "Authorization", value: "Bearer secret"), "inline header lookup should use the same stable header ID as parsed headers")
        let bodyLocation = (rawRequest as NSString).range(of: "body").location
        expect(HeaderInspector.headerLine(in: rawRequest, atUTF16Location: bodyLocation) == nil, "inline header lookup should ignore body lines")

        let serviceRequest = """
        GET / HTTP/1.1
        X-Service: service.demo

        """
        let serviceSelection = (serviceRequest as NSString).range(of: "Service")
        expect(HeaderInspector.headerName(in: serviceRequest, selectedUTF16Range: serviceSelection) == "X-Service", "partial header-name selection should resolve to the full header name")
        let serviceValueSelection = (serviceRequest as NSString).range(of: "service")
        expect(HeaderInspector.headerName(in: serviceRequest, selectedUTF16Range: serviceValueSelection) == "X-Service", "partial header-line selection should resolve to the full header name")

        let curl = CurlConverter.rawToCurl(
            """
            GET / HTTP/1.1
            Host: example.com
            Authorization: Bearer secret
            X-Trace: keep
            Cookie: sid=123

            """,
            manuallyStruckIDs: [],
            redactionKeywords: ["auth", "cookie"],
            redactMatchingKeywords: true
        ) ?? ""
        expect(!curl.contains("Authorization"), "curl export should omit Authorization")
        expect(!curl.contains("Cookie"), "curl export should omit Cookie")
        expect(curl.contains("X-Trace: keep"), "curl export should preserve unstruck headers")
        let queryCurl = CurlConverter.rawToCurl(
            """
            GET /admin?appId=13&auth_token=secret HTTP/1.1
            Host: example.com

            """,
            redactionKeywords: ["auth"],
            redactMatchingKeywords: true
        ) ?? ""
        expect(queryCurl.contains("/admin?appId=13"), "curl export should preserve unstruck query params")
        expect(!queryCurl.contains("auth_token"), "curl export should omit struck query params")

        let matches = SearchEngine.matches(in: "Token token TOKEN", query: "token")
        expect(matches.map(\.text) == ["Token", "token", "TOKEN"], "search should be case-insensitive")
        expect(matches.map(\.range.location) == [0, 6, 12], "search ranges should point to original text")
        expect(SearchEngine.nextIndex(after: 1, matchCount: 2) == 0, "next search index should wrap")
        expect(SearchEngine.previousIndex(before: 0, matchCount: 2) == 1, "previous search index should wrap")

        let builtInDefaultHeaders = DefaultHeader.builtInDefaults
        expect(builtInDefaultHeaders.map(\.name) == ["User-Agent", "Accept"], "built-in defaults should only include generic headers")
        expect(builtInDefaultHeaders.map(\.value) == ["RawSend/1.0", "*/*"], "built-in defaults should not include internal user agents or X-prefixed headers")
        expect(AppPreferences().appLanguage == .english, "app language should default to English")
        expect(Localizer.text(.send, language: AppPreferences().appLanguage) == "Send", "default language should render English UI labels")
        expect(Localizer.text(.send, language: .spanish) == "Enviar", "Spanish UI labels should be available")
        expect(Localizer.missingKeys(for: .spanish).isEmpty, "Spanish translations should cover every UI key")
        expect(Localizer.format(.bodyBytes, language: .spanish, 8) == "Body: 8B", "localized format strings should work")
        expect(!AppPreferences().followRedirects, "follow redirects should default to false")
        expect(AppPreferences().redactMatchingHeaders, "keyword redaction should default to enabled")
        expect(AppPreferences().importantHeaderNames == HeaderInspector.defaultImportantHeaderNames, "important header names should be configurable with stable defaults")

        let debugInfo = ResponseDebugInfo(
            errorMessage: "offline",
            scheme: "https",
            request: HTTPRequest(method: "GET", host: "example.invalid", path: "/", headers: [
                ("X-Debug-LogId", "external-log-id"),
            ]),
            url: "https://example.invalid/",
            localLogPath: "/tmp/rawsend-check.jsonl",
            logID: "rawsend-check-logid"
        )
        expect(debugInfo.copyText.contains("Log ID: rawsend-check-logid"), "debug copy text should include RawSend log id")
        expect(!debugInfo.copyText.contains("external-log-id"), "debug copy text should use RawSend-generated log id")
        let tempLogURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawsend-check-\(UUID().uuidString).jsonl")
        ErrorLogStore.append(debugInfo, to: tempLogURL)
        let tempLog = (try? String(contentsOf: tempLogURL, encoding: .utf8)) ?? ""
        expect(tempLog.contains(#""logID":"rawsend-check-logid""#), "local error log should include RawSend log id")
        try? FileManager.default.removeItem(at: tempLogURL)

        if failures.isEmpty {
            print("RawSendChecks passed")
        } else {
            for failure in failures {
                fputs("FAIL: \(failure)\n", stderr)
            }
            exit(1)
        }
    }
}
