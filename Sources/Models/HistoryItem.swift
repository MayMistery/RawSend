import Foundation

struct HistoryResponse: Codable, Hashable {
    let fullText: String
    let statusCode: Int
    let statusText: String
    let elapsed: TimeInterval
    let size: Int

    init(response: HTTPResponse) {
        self.fullText = response.fullResponseText
        self.statusCode = response.statusCode
        self.statusText = response.statusText
        self.elapsed = response.elapsed
        self.size = response.size
    }
}

/// 历史记录条目
struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let rawText: String
    let method: String
    let host: String
    let path: String
    let timestamp: Date
    let environmentName: String?
    var httpResponse: HistoryResponse?
    var httpsResponse: HistoryResponse?

    var displayTitle: String {
        "\(method) \(host)\(path)"
    }

    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: timestamp)
    }

    init(rawText: String, request: HTTPRequest, environmentName: String?) {
        self.id = UUID()
        self.rawText = rawText
        self.method = request.method
        self.host = request.host
        self.path = request.path
        self.timestamp = Date()
        self.environmentName = environmentName
        self.httpResponse = nil
        self.httpsResponse = nil
    }

    mutating func updateResponses(http: HTTPResponse?, https: HTTPResponse?) {
        self.httpResponse = http.map(HistoryResponse.init)
        self.httpsResponse = https.map(HistoryResponse.init)
    }
}
