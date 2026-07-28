import Foundation

struct ResponseDebugInfo: Hashable {
    let timestamp: Date
    let errorMessage: String
    let scheme: String
    let method: String
    let host: String
    let path: String
    let url: String
    let logID: String
    let localLogPath: String

    init(
        errorMessage: String,
        scheme: String,
        request: HTTPRequest,
        url: String,
        localLogPath: String,
        timestamp: Date = Date(),
        logID: String? = nil
    ) {
        self.timestamp = timestamp
        self.errorMessage = errorMessage
        self.scheme = scheme
        self.method = request.method
        self.host = request.host
        self.path = request.path
        self.url = url
        self.logID = logID ?? Self.makeLogID(timestamp: timestamp)
        self.localLogPath = localLogPath
    }

    var copyText: String {
        [
            "RawSend send error",
            "Time: \(Self.timestampString(timestamp))",
            "Error: \(errorMessage)",
            "Log ID: \(logID)",
            "Request: \(method) \(url)",
            "Host: \(host)",
            "Path: \(path)",
            "Scheme: \(scheme)",
            "Local log: \(localLogPath)",
        ].joined(separator: "\n")
    }

    private static func makeLogID(timestamp: Date) -> String {
        let compactTime = timestampString(timestamp)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return "rawsend-\(compactTime)-\(suffix)"
    }

    private static func timestampString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// HTTP 响应结构
struct HTTPResponse: Identifiable {
    let id = UUID()
    let statusCode: Int
    let statusText: String
    let headers: [(String, String)]
    let body: Data
    let bodyString: String
    let elapsed: TimeInterval
    let size: Int
    let error: String?
    let debugInfo: ResponseDebugInfo?
    private let archivedFullText: String?
    private let cachedFormattedBody: String
    private let cachedFullResponseText: String
    let lineIndex: TextLineIndex

    var isRedirect: Bool {
        (300..<400).contains(statusCode)
    }

    var locationHeader: String? {
        headers.first { $0.0.lowercased() == "location" }?.1
    }

    /// 从 HTTPURLResponse + Data 构建
    init(
        urlResponse: HTTPURLResponse?,
        data: Data,
        elapsed: TimeInterval,
        errorMessage: String? = nil,
        debugInfo: ResponseDebugInfo? = nil
    ) {
        let formatStarted = Date()
        let statusCode = urlResponse?.statusCode ?? 0
        let statusText = urlResponse.map { HTTPURLResponse.localizedString(forStatusCode: $0.statusCode) } ?? "Error"
        let headers = (urlResponse?.allHeaderFields as? [String: String])?.map { ($0.key, $0.value) } ?? []
        let bodyString = String(data: data, encoding: .utf8) ?? "<binary data: \(data.count) bytes>"
        let formattedBody = Self.formatBody(data: data, bodyString: bodyString)

        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = data
        self.bodyString = bodyString
        self.elapsed = elapsed
        self.size = data.count
        self.error = errorMessage
        self.debugInfo = debugInfo
        self.archivedFullText = nil
        let fullResponseText = Self.makeFullResponseText(
            statusCode: statusCode,
            statusText: statusText,
            headers: headers,
            formattedBody: formattedBody,
            error: errorMessage,
            debugInfo: debugInfo
        )
        self.cachedFormattedBody = formattedBody
        self.cachedFullResponseText = fullResponseText
        self.lineIndex = TextLineIndex(text: fullResponseText)
        PerformanceLogStore.appendIfSlow(
            operation: "response-format",
            source: "response",
            elapsed: Date().timeIntervalSince(formatStarted),
            textLength: data.count,
            queryLength: 0,
            matchCount: 0
        )
    }

    /// 错误响应
    static func error(_ message: String, elapsed: TimeInterval = 0, debugInfo: ResponseDebugInfo? = nil) -> HTTPResponse {
        HTTPResponse(urlResponse: nil, data: Data(), elapsed: elapsed, errorMessage: message, debugInfo: debugInfo)
    }

    static func archived(_ response: HistoryResponse) -> HTTPResponse {
        HTTPResponse(
            statusCode: response.statusCode,
            statusText: response.statusText,
            headers: [],
            body: Data(),
            bodyString: "",
            elapsed: response.elapsed,
            size: response.size,
            error: nil,
            debugInfo: nil,
            archivedFullText: response.fullText
        )
    }

    private init(
        statusCode: Int,
        statusText: String,
        headers: [(String, String)],
        body: Data,
        bodyString: String,
        elapsed: TimeInterval,
        size: Int,
        error: String?,
        debugInfo: ResponseDebugInfo?,
        archivedFullText: String?
    ) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.bodyString = bodyString
        self.elapsed = elapsed
        self.size = size
        self.error = error
        self.debugInfo = debugInfo
        self.archivedFullText = archivedFullText
        let fullResponseText = archivedFullText ?? Self.makeFullResponseText(
            statusCode: statusCode,
            statusText: statusText,
            headers: headers,
            formattedBody: bodyString,
            error: error,
            debugInfo: debugInfo
        )
        self.cachedFormattedBody = bodyString
        self.cachedFullResponseText = fullResponseText
        self.lineIndex = TextLineIndex(text: fullResponseText)
    }

    /// 格式化的响应文本（含状态行+头+body）
    var fullResponseText: String {
        cachedFullResponseText
    }

    /// 插件分析使用的响应文本：保留未 pretty-print 的原始 body。
    var rawResponseText: String {
        if archivedFullText != nil {
            return cachedFullResponseText
        }
        return Self.makeFullResponseText(
            statusCode: statusCode,
            statusText: statusText,
            headers: headers,
            formattedBody: bodyString,
            error: error,
            debugInfo: debugInfo
        )
    }

    /// 尝试格式化 JSON
    var formattedBody: String {
        cachedFormattedBody
    }

    private static func formatBody(data: Data, bodyString: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return bodyString
    }

    private static func makeFullResponseText(
        statusCode: Int,
        statusText: String,
        headers: [(String, String)],
        formattedBody: String,
        error: String?,
        debugInfo: ResponseDebugInfo?
    ) -> String {
        if let error, statusCode == 0 {
            return debugInfo?.copyText ?? "ERROR: \(error)"
        }
        var lines: [String] = []
        lines.append("HTTP/1.1 \(statusCode) \(statusText)")
        for (name, value) in headers {
            lines.append("\(name): \(value)")
        }
        lines.append("")
        lines.append(formattedBody)
        return lines.joined(separator: "\n")
    }
}
