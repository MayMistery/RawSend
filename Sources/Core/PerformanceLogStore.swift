import Foundation

struct PerformanceLogEvent: Encodable {
    let timestamp: String
    let operation: String
    let source: String
    let elapsedMilliseconds: Int
    let thresholdMilliseconds: Int
    let textLength: Int
    let queryLength: Int
    let matchCount: Int

    init(
        operation: String,
        source: String,
        elapsedMilliseconds: Int,
        thresholdMilliseconds: Int,
        textLength: Int,
        queryLength: Int,
        matchCount: Int,
        timestamp: Date = Date()
    ) {
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
        self.operation = operation
        self.source = source
        self.elapsedMilliseconds = elapsedMilliseconds
        self.thresholdMilliseconds = thresholdMilliseconds
        self.textLength = textLength
        self.queryLength = queryLength
        self.matchCount = matchCount
    }
}

enum PerformanceLogStore {
    static let thresholdMilliseconds = 200

    static var logFileURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RawSend", isDirectory: true)
            .appendingPathComponent("performance.jsonl")
    }

    static func appendIfSlow(
        operation: String,
        source: String,
        elapsed: TimeInterval,
        textLength: Int,
        queryLength: Int,
        matchCount: Int,
        threshold: TimeInterval = Double(thresholdMilliseconds) / 1_000,
        to fileURL: URL = logFileURL
    ) {
        guard elapsed >= threshold else { return }
        append(PerformanceLogEvent(
            operation: operation,
            source: source,
            elapsedMilliseconds: Int((elapsed * 1_000).rounded()),
            thresholdMilliseconds: Int((threshold * 1_000).rounded()),
            textLength: textLength,
            queryLength: queryLength,
            matchCount: matchCount
        ), to: fileURL)
    }

    static func append(_ event: PerformanceLogEvent, to fileURL: URL = logFileURL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(event) else { return }

        var line = data
        line.append(0x0A)

        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                return
            }
        } else {
            try? line.write(to: fileURL, options: .atomic)
        }

        NSLog(
            "RawSend slow %@ [%@]: %dms threshold=%dms text=%d query=%d matches=%d",
            event.operation,
            event.source,
            event.elapsedMilliseconds,
            event.thresholdMilliseconds,
            event.textLength,
            event.queryLength,
            event.matchCount
        )
    }
}
