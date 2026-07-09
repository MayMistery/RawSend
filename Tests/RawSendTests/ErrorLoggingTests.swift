import Foundation
import Testing
@testable import RawSend

@Suite("Error logging")
struct ErrorLoggingTests {
    @Test func sendErrorDebugInfoGeneratesRawSendLogID() {
        let request = HTTPRequest(
            method: "GET",
            host: "example.invalid",
            path: "/api/tools",
            headers: [
                ("X-Debug-LogId", "external-log-id"),
                ("Traceparent", "00-trace"),
            ]
        )

        let debugInfo = ResponseDebugInfo(
            errorMessage: "A server with the specified hostname could not be found.",
            scheme: "https",
            request: request,
            url: "https://example.invalid/api/tools",
            localLogPath: "/tmp/rawsend-send-errors.jsonl",
            timestamp: Date(timeIntervalSince1970: 0)
        )

        #expect(debugInfo.logID.hasPrefix("rawsend-19700101T000000Z-"))
        #expect(!debugInfo.copyText.contains("external-log-id"))
        #expect(debugInfo.copyText.contains("Log ID: \(debugInfo.logID)"))
        #expect(debugInfo.copyText.contains("Local log: /tmp/rawsend-send-errors.jsonl"))
    }

    @Test func errorLogStoreAppendsJSONLines() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawsend-error-log-\(UUID().uuidString)")
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let request = HTTPRequest(
            method: "GET",
            host: "example.invalid",
            path: "/",
            headers: []
        )
        let debugInfo = ResponseDebugInfo(
            errorMessage: "offline",
            scheme: "https",
            request: request,
            url: "https://example.invalid/",
            localLogPath: fileURL.path,
            timestamp: Date(timeIntervalSince1970: 0),
            logID: "rawsend-test-logid"
        )

        ErrorLogStore.append(debugInfo, to: fileURL)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains(#""logID":"rawsend-test-logid""#))
        #expect(content.contains(#""error":"offline""#))
        #expect(content.hasSuffix("\n"))
    }
}
