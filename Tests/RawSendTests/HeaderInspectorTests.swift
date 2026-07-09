import Foundation
import Testing
@testable import RawSend

@Suite("Header inspector")
struct HeaderInspectorTests {
    @Test func importantHeadersAreMatchedCaseInsensitivelyAndShownInPreferredOrder() {
        let lines = HeaderInspector.makeHeaderLines(from: [
            ("host", "example.com"),
            ("X-Env", "test"),
            ("X-Service", "rawsend"),
            ("X-Lane", "local"),
        ], manuallyStruckIDs: [], keywords: [])

        let important = HeaderInspector.importantHeaders(from: lines)
        let configured = HeaderInspector.importantHeaders(from: lines, names: ["x-service", "x-env"])

        #expect(important.isEmpty)
        #expect(configured.map(\.name) == ["X-Service", "X-Env"])
        #expect(configured.map(\.value) == ["rawsend", "test"])
    }

    @Test func sensitiveKeywordsStrikeHeadersByNameOrValueButKeepThemVisible() {
        let lines = HeaderInspector.makeHeaderLines(from: [
            ("Authorization", "Bearer abc"),
            ("X-Trace", "contains-token-value"),
            ("Accept", "application/json"),
            ("Cookie", "sid=123"),
        ], manuallyStruckIDs: [], keywords: ["token", "AUTH", "cookie"])

        #expect(lines.map(\.isStruck) == [true, true, false, true])
        #expect(lines.map(\.displayText) == [
            "Authorization: Bearer abc",
            "X-Trace: contains-token-value",
            "Accept: application/json",
            "Cookie: sid=123",
        ])
    }

    @Test func manualStrikeAndKeywordStrikeAreExcludedFromSendableHeaders() {
        let baseline = HeaderInspector.makeHeaderLines(from: [
            ("X-Manual", "keep-visible"),
            ("X-Auth-Token", "secret"),
            ("Accept", "*/*"),
        ], manuallyStruckIDs: [], keywords: ["token"])
        let manuallyStruckID = baseline[0].id

        let lines = HeaderInspector.makeHeaderLines(from: [
            ("X-Manual", "keep-visible"),
            ("X-Auth-Token", "secret"),
            ("Accept", "*/*"),
        ], manuallyStruckIDs: [manuallyStruckID], keywords: ["token"])

        let sendable = HeaderInspector.sendableHeaders(from: lines)

        #expect(lines.map(\.isStruck) == [true, true, false])
        #expect(sendable.map { "\($0.0): \($0.1)" } == ["Accept: */*"])
    }

    @Test func appPreferencesDecodeMissingRedactionKeywordsWithDefaultValues() throws {
        let data = #"{"timeoutSeconds":10,"followRedirects":true,"ignoreTLSErrors":false,"maxHistoryCount":12,"includDefaultHeadersInCurl":false}"#
            .data(using: .utf8)!

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        #expect(preferences.redactionKeywords == ["token", "auth", "cookie"])
        #expect(preferences.redactMatchingHeaders)
        #expect(preferences.importantHeaderNames == HeaderInspector.defaultImportantHeaderNames)
        #expect(preferences.timeoutSeconds == 10)
        #expect(preferences.followRedirects)
        #expect(!preferences.ignoreTLSErrors)
        #expect(preferences.maxHistoryCount == 12)
        #expect(!preferences.includDefaultHeadersInCurl)
    }

    @Test func appPreferencesFollowRedirectsDefaultsToFalse() {
        #expect(!AppPreferences().followRedirects)
    }

    @Test func appPreferencesRedactMatchingHeadersDefaultsToTrue() {
        #expect(AppPreferences().redactMatchingHeaders)
    }

    @Test func builtInDefaultHeadersOnlyIncludeGenericValues() {
        let defaults = DefaultHeader.builtInDefaults

        #expect(defaults.map(\.name) == ["User-Agent", "Accept"])
        #expect(defaults.map(\.value) == ["RawSend/1.0", "*/*"])
        #expect(defaults.allSatisfy { $0.isEnabled })
        #expect(defaults.allSatisfy { !$0.name.lowercased().hasPrefix("x-") })
    }
}
