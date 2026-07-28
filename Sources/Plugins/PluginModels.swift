import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    static func fromEncodable<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> JSONValue {
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try decoder.decode(type, from: data)
    }
}

enum PluginRuntimeKind: String, Codable, Sendable {
    case process
    case python
    case native
}

struct PluginRuntimeManifest: Codable, Equatable, Sendable {
    var kind: PluginRuntimeKind
    var entrypoint: String
    var interpreter: String?
    var arguments: [String]?
    var architectures: [String: String]?
}

struct PluginAPIVersion: Codable, Equatable, Sendable {
    var major: Int
    var minor: Int
}

struct PluginManifest: Codable, Identifiable, Equatable, Sendable {
    static let supportedManifestVersion = 1
    static let hostAPI = PluginAPIVersion(major: 1, minor: 0)

    var manifestVersion: Int
    var id: String
    var name: String
    var version: String
    var description: String?
    var hostAPI: PluginAPIVersion
    var runtime: PluginRuntimeManifest
    var hooks: [String]
    var permissions: [String]
    var defaultEnabled: Bool?
    var settings: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case id
        case name
        case version
        case description
        case hostAPI = "host_api"
        case runtime
        case hooks
        case permissions
        case defaultEnabled = "default_enabled"
        case settings
    }
}

struct PluginState: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var grantedPermissions: Set<String>
    var settings: [String: JSONValue]

    init(
        isEnabled: Bool = false,
        grantedPermissions: Set<String> = [],
        settings: [String: JSONValue] = [:]
    ) {
        self.isEnabled = isEnabled
        self.grantedPermissions = grantedPermissions
        self.settings = settings
    }
}

struct PluginDescriptor: Identifiable, Equatable {
    let manifest: PluginManifest
    let bundleURL: URL
    var state: PluginState
    var status: PluginStatus
    var diagnostic: String?

    var id: String { manifest.id }
}

enum PluginStatus: String, Codable, Equatable, Sendable {
    case disabled
    case ready
    case running
    case failed
    case incompatible
}

struct PluginRequestField: Codable, Equatable, Sendable, Identifiable {
    enum Location: String, Codable, Sendable {
        case query
        case form
        case json
    }

    let id: String
    let location: Location
    let name: String
    let path: String
    let value: String
}

struct PluginRequestSnapshot: Codable, Equatable, Sendable {
    let method: String
    let scheme: String?
    let host: String
    let path: String
    let headers: [PluginHeader]
    let body: String
    let raw: String
    let fields: [PluginRequestField]
}

struct PluginHeader: Codable, Equatable, Sendable {
    let name: String
    let value: String
}

struct PluginResponseSnapshot: Codable, Equatable, Sendable {
    let id: String
    let statusCode: Int
    let headers: [PluginHeader]
    let bodyText: String
    let raw: String
    let displayText: String
    let elapsedMilliseconds: Double
    let size: Int
    let error: String?
}

struct PluginMutation: Codable, Equatable, Sendable {
    let targetID: String
    let replacement: String

    enum CodingKeys: String, CodingKey {
        case targetID = "target_id"
        case replacement
    }
}

struct PluginRequestVariant: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let scheme: String?
    let mutations: [PluginMutation]
    let metadata: [String: String]
}

struct PluginAnnotation: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let responseID: String
    let value: String?
    let location: Int?
    let length: Int?
    let line: Int?
    let severity: String
    let title: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case id
        case responseID = "response_id"
        case value
        case location
        case length
        case line
        case severity
        case title
        case message
    }
}

struct PluginFinding: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let pluginID: String?
    let responseID: String?
    let title: String
    let summary: String
    let severity: String
    let status: String
    let details: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id
        case pluginID = "plugin_id"
        case responseID = "response_id"
        case title
        case summary
        case severity
        case status
        case details
    }
}

struct PluginEventResult: Codable, Equatable, Sendable {
    var variants: [PluginRequestVariant]
    var annotations: [PluginAnnotation]
    var findings: [PluginFinding]
    var statusMessage: String?

    enum CodingKeys: String, CodingKey {
        case variants
        case annotations
        case findings
        case statusMessage = "status_message"
    }

    init(
        variants: [PluginRequestVariant] = [],
        annotations: [PluginAnnotation] = [],
        findings: [PluginFinding] = [],
        statusMessage: String? = nil
    ) {
        self.variants = variants
        self.annotations = annotations
        self.findings = findings
        self.statusMessage = statusMessage
    }
}

struct PluginExchangeSnapshot: Codable, Equatable, Sendable {
    let id: String
    let request: PluginRequestSnapshot
    let response: PluginResponseSnapshot
    let originPluginID: String?
    let variantID: String?
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case request
        case response
        case originPluginID = "origin_plugin_id"
        case variantID = "variant_id"
        case metadata
    }
}

struct PluginInitializeParams: Codable, Sendable {
    let host: PluginHostInfo
    let plugin: PluginManifest
    let bundlePath: String
    let grantedPermissions: [String]
    let settings: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case host
        case plugin
        case bundlePath = "bundle_path"
        case grantedPermissions = "granted_permissions"
        case settings
    }
}

struct PluginHostInfo: Codable, Equatable, Sendable {
    let name: String
    let version: String
    let api: PluginAPIVersion
    let platform: String
    let architecture: String
}

struct PluginSendPlanParams: Codable, Sendable {
    let request: PluginRequestSnapshot
    let schemes: [String]
    let settings: [String: JSONValue]
}

struct PluginExchangeParams: Codable, Sendable {
    let exchange: PluginExchangeSnapshot
    let settings: [String: JSONValue]
}

struct PluginBatchParams: Codable, Sendable {
    let baseline: [PluginExchangeSnapshot]
    let variants: [PluginExchangeSnapshot]
    let settings: [String: JSONValue]
}

struct ResponseAnnotation: Identifiable, Equatable {
    let id: String
    let responseID: UUID
    let range: NSRange
    let severity: String
    let title: String
    let message: String
}
