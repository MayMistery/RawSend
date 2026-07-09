import Foundation
import Testing
@testable import RawSend

@Suite("Performance logging")
struct PerformanceLogStoreTests {
    @Test func slowOperationAppendsJSONLine() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawsend-performance-\(UUID().uuidString)")
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let event = PerformanceLogEvent(
            operation: "search",
            source: "request",
            elapsedMilliseconds: 251,
            thresholdMilliseconds: 200,
            textLength: 1024,
            queryLength: 5,
            matchCount: 2
        )

        PerformanceLogStore.append(event, to: fileURL)
        PerformanceLogStore.appendIfSlow(
            operation: "highlight",
            source: "response",
            elapsed: 0.251,
            textLength: 2048,
            queryLength: 4,
            matchCount: 3,
            to: fileURL
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains(#""operation":"search""#))
        #expect(content.contains(#""operation":"highlight""#))
        #expect(content.contains(#""source":"request""#))
        #expect(content.contains(#""source":"response""#))
        #expect(content.contains(#""elapsedMilliseconds":251"#))
        #expect(content.hasSuffix("\n"))
    }
}
