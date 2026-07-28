import Foundation

/// JSON 文件持久化管理
class PersistenceManager {
    static let shared = PersistenceManager()

    private let baseURL: URL
    private let ioQueue = DispatchQueue(label: "com.rawsend.persistence", qos: .utility)

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(baseURL: appSupport.appendingPathComponent("RawSend", isDirectory: true))
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - Environments

    func loadEnvironments() -> [Environment] {
        load(from: "environments.json") ?? [
            Environment(name: "Default", variables: [
                .init(key: "host", value: "example.com"),
            ])
        ]
    }

    func saveEnvironments(_ environments: [Environment]) {
        save(environments, to: "environments.json")
    }

    // MARK: - Default Headers

    func loadDefaultHeaders() -> [DefaultHeader] {
        load(from: "defaults.json") ?? DefaultHeader.builtInDefaults
    }

    func saveDefaultHeaders(_ headers: [DefaultHeader]) {
        save(headers, to: "defaults.json")
    }

    // MARK: - History

    func loadHistory() -> [HistoryItem] {
        load(from: "history.json") ?? []
    }

    func saveHistory(_ history: [HistoryItem]) {
        let url = baseURL.appendingPathComponent("history.json")
        ioQueue.async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(history) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Preferences

    func loadPreferences() -> AppPreferences {
        load(from: "preferences.json") ?? AppPreferences()
    }

    func savePreferences(_ prefs: AppPreferences) {
        save(prefs, to: "preferences.json")
    }

    // MARK: - Plugins

    func loadPluginStates() -> [String: PluginState] {
        load(from: "plugins.json") ?? [:]
    }

    func savePluginStates(_ states: [String: PluginState]) {
        save(states, to: "plugins.json")
    }

    // MARK: - Private

    private func load<T: Decodable>(from filename: String) -> T? {
        let url = baseURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = baseURL.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
