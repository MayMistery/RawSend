import Foundation

/// 环境配置
struct Environment: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var variables: [Variable]

    struct Variable: Codable, Identifiable, Hashable {
        let id: UUID
        var key: String
        var value: String
        var isSensitive: Bool

        init(key: String = "", value: String = "", isSensitive: Bool = false) {
            self.id = UUID()
            self.key = key
            self.value = value
            self.isSensitive = isSensitive
        }
    }

    init(name: String, variables: [Variable] = []) {
        self.id = UUID()
        self.name = name
        self.variables = variables
    }
}

/// 全局默认头配置
struct DefaultHeader: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var value: String
    var isEnabled: Bool

    static let builtInDefaults: [DefaultHeader] = [
        DefaultHeader(name: "User-Agent", value: "RawSend/1.0"),
        DefaultHeader(name: "Accept", value: "*/*"),
    ]

    init(name: String = "", value: String = "", isEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }
}

/// 应用偏好设置
struct AppPreferences: Codable {
    static let defaultCodexUserPrompt = "Identify request and response parameters that may affect security testing. Focus on authentication, user identity, tenant, environment, routing, permission boundaries, authorization bypass, replay, and injection-related fields. When I ask you to strike authentication-related parameters, directly suggest the matching Header and URL parameter strike actions."

    var appLanguage: AppLanguage = .english
    var timeoutSeconds: Double = 30
    var followRedirects: Bool = false
    var ignoreTLSErrors: Bool = true
    var maxHistoryCount: Int = 500
    var includDefaultHeadersInCurl: Bool = true
    var redactionKeywords: [String] = HeaderInspector.defaultRedactionKeywords
    var redactMatchingHeaders: Bool = true
    var importantHeaderNames: [String] = HeaderInspector.defaultImportantHeaderNames
    var codexUserPrompt: String = AppPreferences.defaultCodexUserPrompt

    enum CodingKeys: String, CodingKey {
        case appLanguage
        case timeoutSeconds
        case followRedirects
        case ignoreTLSErrors
        case maxHistoryCount
        case includDefaultHeadersInCurl
        case redactionKeywords
        case redactMatchingHeaders
        case importantHeaderNames
        case codexUserPrompt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .english
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 30
        followRedirects = try container.decodeIfPresent(Bool.self, forKey: .followRedirects) ?? false
        ignoreTLSErrors = try container.decodeIfPresent(Bool.self, forKey: .ignoreTLSErrors) ?? true
        maxHistoryCount = try container.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 500
        includDefaultHeadersInCurl = try container.decodeIfPresent(Bool.self, forKey: .includDefaultHeadersInCurl) ?? true
        redactionKeywords = try container.decodeIfPresent([String].self, forKey: .redactionKeywords)
            ?? HeaderInspector.defaultRedactionKeywords
        redactMatchingHeaders = try container.decodeIfPresent(Bool.self, forKey: .redactMatchingHeaders) ?? true
        importantHeaderNames = try container.decodeIfPresent([String].self, forKey: .importantHeaderNames)
            ?? HeaderInspector.defaultImportantHeaderNames
        codexUserPrompt = try container.decodeIfPresent(String.self, forKey: .codexUserPrompt)
            ?? AppPreferences.defaultCodexUserPrompt
    }
}
