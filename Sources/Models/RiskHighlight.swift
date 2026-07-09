import Foundation

struct RiskHighlight: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case request
        case response
    }

    let id: UUID
    var source: Source
    var line: Int
    var severity: String
    var reason: String

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case line
        case severity
        case reason
    }

    init(id: UUID = UUID(), source: Source, line: Int, severity: String = "medium", reason: String) {
        self.id = id
        self.source = source
        self.line = line
        self.severity = severity
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try container.decode(Source.self, forKey: .source)
        line = try container.decode(Int.self, forKey: .line)
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? "medium"
        reason = try container.decode(String.self, forKey: .reason)
    }
}
