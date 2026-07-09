import Foundation

/// 解析后的 HTTP 请求结构
struct HTTPRequest: Codable, Identifiable {
    let id: UUID
    var method: String
    var host: String
    var path: String
    var httpVersion: String
    var headers: [(String, String)]
    var body: String

    var displayTitle: String {
        "\(method) \(host)\(path)"
    }

    init(method: String = "GET", host: String = "", path: String = "/",
         httpVersion: String = "HTTP/1.1", headers: [(String, String)] = [], body: String = "") {
        self.id = UUID()
        self.method = method
        self.host = host
        self.path = path
        self.httpVersion = httpVersion
        self.headers = headers
        self.body = body
    }

    // Codable 手动实现（元组数组不自动 Codable）
    enum CodingKeys: String, CodingKey {
        case id, method, host, path, httpVersion, headers, body
    }

    struct HeaderPair: Codable {
        let name: String
        let value: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encode(host, forKey: .host)
        try container.encode(path, forKey: .path)
        try container.encode(httpVersion, forKey: .httpVersion)
        try container.encode(body, forKey: .body)
        let pairs = headers.map { HeaderPair(name: $0.0, value: $0.1) }
        try container.encode(pairs, forKey: .headers)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        host = try container.decode(String.self, forKey: .host)
        path = try container.decode(String.self, forKey: .path)
        httpVersion = try container.decode(String.self, forKey: .httpVersion)
        body = try container.decode(String.self, forKey: .body)
        let pairs = try container.decode([HeaderPair].self, forKey: .headers)
        headers = pairs.map { ($0.name, $0.value) }
    }
}
