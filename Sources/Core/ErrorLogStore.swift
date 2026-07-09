import Foundation

enum ErrorLogStore {
    static var logFileURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RawSend", isDirectory: true)
            .appendingPathComponent("send-errors.jsonl")
    }

    static func append(_ debugInfo: ResponseDebugInfo, to fileURL: URL = logFileURL) {
        let entry = ErrorLogEntry(debugInfo: debugInfo)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry) else { return }

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
    }
}

private struct ErrorLogEntry: Encodable {
    let timestamp: String
    let error: String
    let logID: String
    let method: String
    let url: String
    let host: String
    let path: String
    let scheme: String

    init(debugInfo: ResponseDebugInfo) {
        timestamp = ISO8601DateFormatter().string(from: debugInfo.timestamp)
        error = debugInfo.errorMessage
        logID = debugInfo.logID
        method = debugInfo.method
        url = debugInfo.url
        host = debugInfo.host
        path = debugInfo.path
        scheme = debugInfo.scheme
    }
}
