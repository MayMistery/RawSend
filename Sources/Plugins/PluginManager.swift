import Foundation
import Combine

struct PlannedPluginVariant {
    let pluginID: String
    let variant: PluginRequestVariant
}

@MainActor
final class PluginManager: ObservableObject {
    @Published private(set) var plugins: [PluginDescriptor] = []
    @Published private(set) var findings: [PluginFinding] = []
    @Published private(set) var annotations: [ResponseAnnotation] = []
    @Published private(set) var discoveryDiagnostics: [String] = []
    @Published private(set) var statusMessages: [String: String] = [:]

    private var states: [String: PluginState] = [:]
    private var loadedManifests: [String: LoadedPluginManifest] = [:]
    private var runtimes: [String: any PluginRuntimeClient] = [:]
    private let discoveryDirectories: [URL]
    private let persistence: PersistenceManager

    init(
        discoveryDirectories: [URL] = PluginDiscovery.defaultDirectories,
        persistence: PersistenceManager = .shared
    ) {
        self.discoveryDirectories = discoveryDirectories
        self.persistence = persistence
    }

    func reload() async {
        await stopAll()
        states = persistence.loadPluginStates()
        loadedManifests.removeAll()
        discoveryDiagnostics.removeAll()

        var descriptors: [PluginDescriptor] = []
        for bundle in PluginDiscovery.discover(in: discoveryDirectories) {
            do {
                let loaded = try PluginManifestLoader.load(bundleURL: bundle)
                var state = states[loaded.manifest.id] ?? PluginState(
                    isEnabled: loaded.manifest.defaultEnabled ?? false,
                    grantedPermissions: Set(loaded.manifest.permissions),
                    settings: loaded.manifest.settings ?? [:]
                )
                for (key, value) in loaded.manifest.settings ?? [:] where state.settings[key] == nil {
                    state.settings[key] = value
                }
                states[loaded.manifest.id] = state
                loadedManifests[loaded.manifest.id] = loaded
                descriptors.append(
                    PluginDescriptor(
                        manifest: loaded.manifest,
                        bundleURL: bundle,
                        state: state,
                        status: state.isEnabled ? .ready : .disabled,
                        diagnostic: nil
                    )
                )
            } catch {
                discoveryDiagnostics.append("\(bundle.lastPathComponent): \(error.localizedDescription)")
            }
        }
        plugins = descriptors.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
        persistence.savePluginStates(states)

        for plugin in plugins where plugin.state.isEnabled {
            do {
                try await startRuntime(pluginID: plugin.id)
            } catch {
                updateStatus(pluginID: plugin.id, status: .failed, diagnostic: error.localizedDescription)
            }
        }
    }

    func setEnabled(_ enabled: Bool, pluginID: String) {
        guard var state = states[pluginID],
              let manifest = loadedManifests[pluginID]?.manifest else { return }
        state.isEnabled = enabled
        if enabled {
            state.grantedPermissions.formUnion(manifest.permissions)
        }
        states[pluginID] = state
        persistence.savePluginStates(states)
        if let index = plugins.firstIndex(where: { $0.id == pluginID }) {
            plugins[index].state = state
            plugins[index].status = enabled ? .ready : .disabled
            plugins[index].diagnostic = nil
        }
        Task {
            if enabled {
                do {
                    try await startRuntime(pluginID: pluginID)
                } catch {
                    updateStatus(pluginID: pluginID, status: .failed, diagnostic: error.localizedDescription)
                }
            } else {
                await stopRuntime(pluginID: pluginID)
            }
        }
    }

    func updateSetting(_ value: JSONValue, key: String, pluginID: String) {
        guard var state = states[pluginID] else { return }
        state.settings[key] = value
        states[pluginID] = state
        persistence.savePluginStates(states)
        if let index = plugins.firstIndex(where: { $0.id == pluginID }) {
            plugins[index].state = state
        }
        guard state.isEnabled else { return }
        Task {
            await stopRuntime(pluginID: pluginID)
            do {
                try await startRuntime(pluginID: pluginID)
            } catch {
                updateStatus(pluginID: pluginID, status: .failed, diagnostic: error.localizedDescription)
            }
        }
    }

    func prepareSend(request: HTTPRequest, schemes: [String]) async -> [PlannedPluginVariant] {
        let snapshot = makeRequestSnapshot(request: request, scheme: nil)
        var variants: [PlannedPluginVariant] = []
        for plugin in activePlugins(hook: "send.plan") {
            do {
                let result: PluginEventResult = try await invoke(
                    pluginID: plugin.id,
                    method: "send.plan",
                    params: PluginSendPlanParams(
                        request: snapshot,
                        schemes: schemes,
                        settings: plugin.state.settings
                    ),
                    timeout: 30
                )
                applyNonResponseResult(result, pluginID: plugin.id)
                variants.append(contentsOf: result.variants.map {
                    PlannedPluginVariant(pluginID: plugin.id, variant: $0)
                })
            } catch {
                pluginFailed(plugin.id, error: error)
            }
        }
        return variants
    }

    func analyze(exchanges: [RequestSender.SentExchange]) async {
        for exchange in exchanges {
            let snapshot = makeExchangeSnapshot(exchange)
            for plugin in activePlugins(hook: "exchange.completed") {
                do {
                    let result: PluginEventResult = try await invoke(
                        pluginID: plugin.id,
                        method: "exchange.completed",
                        params: PluginExchangeParams(exchange: snapshot, settings: plugin.state.settings),
                        timeout: 45
                    )
                    apply(result, pluginID: plugin.id, exchanges: exchanges)
                } catch {
                    pluginFailed(plugin.id, error: error)
                }
            }
        }
    }

    func completeBatch(
        baseline: [RequestSender.SentExchange],
        variants: [RequestSender.SentExchange]
    ) async {
        let grouped = Dictionary(grouping: variants) { $0.originPluginID ?? "" }
        for (pluginID, pluginExchanges) in grouped where !pluginID.isEmpty {
            guard let plugin = activePlugins(hook: "send.batch.completed").first(where: { $0.id == pluginID }) else {
                continue
            }
            do {
                let result: PluginEventResult = try await invoke(
                    pluginID: pluginID,
                    method: "send.batch.completed",
                    params: PluginBatchParams(
                        baseline: baseline.map(makeExchangeSnapshot),
                        variants: pluginExchanges.map(makeExchangeSnapshot),
                        settings: plugin.state.settings
                    ),
                    timeout: 90
                )
                apply(result, pluginID: pluginID, exchanges: baseline + variants)
            } catch {
                pluginFailed(pluginID, error: error)
            }
        }
    }

    func clearResults() {
        findings.removeAll()
        annotations.removeAll()
        statusMessages.removeAll()
    }

    func shutdown() async {
        await stopAll()
    }

    func annotations(for responseID: UUID) -> [ResponseAnnotation] {
        annotations.filter { $0.responseID == responseID }
    }

    private func activePlugins(hook: String) -> [PluginDescriptor] {
        plugins.filter {
            $0.state.isEnabled &&
            $0.status != .failed &&
            $0.manifest.hooks.contains(hook)
        }
    }

    private func startRuntime(pluginID: String) async throws {
        guard runtimes[pluginID] == nil,
              let loaded = loadedManifests[pluginID],
              let state = states[pluginID] else { return }
        let runtime: any PluginRuntimeClient
        if loaded.manifest.runtime.kind == .native {
            runtime = NativePluginRuntime(loaded: loaded)
        } else {
            runtime = ProcessPluginRuntime(
                loaded: loaded,
                hostCallHandler: makeHostCallHandler(pluginID: pluginID)
            )
        }
        runtimes[pluginID] = runtime
        do {
            try await runtime.start(
                initialize: PluginInitializeParams(
                    host: PluginHostInfo(
                        name: "RawSend",
                        version: "1.1.0",
                        api: PluginManifest.hostAPI,
                        platform: "macOS",
                        architecture: PluginPlatform.architecture
                    ),
                    plugin: loaded.manifest,
                    bundlePath: loaded.bundleURL.path,
                    grantedPermissions: Array(state.grantedPermissions).sorted(),
                    settings: state.settings
                )
            )
            updateStatus(pluginID: pluginID, status: .running, diagnostic: nil)
        } catch {
            runtimes.removeValue(forKey: pluginID)
            throw error
        }
    }

    private func stopRuntime(pluginID: String) async {
        if let runtime = runtimes.removeValue(forKey: pluginID) {
            await runtime.stop()
        }
        updateStatus(pluginID: pluginID, status: .disabled, diagnostic: nil)
    }

    private func stopAll() async {
        let current = runtimes.values
        runtimes.removeAll()
        for runtime in current {
            await runtime.stop()
        }
    }

    private func invoke<Params: Encodable, Result: Decodable>(
        pluginID: String,
        method: String,
        params: Params,
        timeout: TimeInterval
    ) async throws -> Result {
        if runtimes[pluginID] == nil {
            try await startRuntime(pluginID: pluginID)
        }
        guard let runtime = runtimes[pluginID] else {
            throw PluginRuntimeError.notStarted
        }
        let value = try await runtime.call(
            method: method,
            params: try JSONValue.fromEncodable(params),
            timeout: timeout
        )
        return try value.decode(Result.self)
    }

    private func makeHostCallHandler(pluginID: String) -> PluginHostCallHandler {
        { [weak self] method, params in
            guard let self else { return .failure(.terminated("host released")) }
            return await self.handleHostCall(pluginID: pluginID, method: method, params: params)
        }
    }

    private func handleHostCall(
        pluginID: String,
        method: String,
        params: JSONValue?
    ) -> Result<JSONValue, PluginRuntimeError> {
        guard let state = states[pluginID] else {
            return .failure(.protocolFailure("Unknown plugin"))
        }
        switch method {
        case "host.info":
            let info = PluginHostInfo(
                name: "RawSend",
                version: "1.1.0",
                api: PluginManifest.hostAPI,
                platform: "macOS",
                architecture: PluginPlatform.architecture
            )
            return Result { try JSONValue.fromEncodable(info) }
                .mapError { .protocolFailure($0.localizedDescription) }
        case "settings.get":
            return .success(.object(state.settings))
        case "ui.status.set":
            guard state.grantedPermissions.contains("ui.status.write"),
                  let message = params?.objectValue?["message"]?.stringValue else {
                return .failure(.protocolFailure("Permission denied or invalid status payload"))
            }
            statusMessages[pluginID] = message
            return .success(.bool(true))
        default:
            return .failure(.protocolFailure("Unsupported Host API method: \(method)"))
        }
    }

    private func makeRequestSnapshot(request: HTTPRequest, scheme: String?) -> PluginRequestSnapshot {
        PluginRequestSnapshot(
            method: request.method,
            scheme: scheme,
            host: request.host,
            path: request.path,
            headers: request.headers.map { PluginHeader(name: $0.0, value: $0.1) },
            body: request.body,
            raw: RequestParser.buildRaw(from: request),
            fields: RequestFieldExtractor.fields(in: request)
        )
    }

    private func makeExchangeSnapshot(_ exchange: RequestSender.SentExchange) -> PluginExchangeSnapshot {
        PluginExchangeSnapshot(
            id: exchange.id.uuidString,
            request: makeRequestSnapshot(request: exchange.request, scheme: exchange.scheme),
            response: PluginResponseSnapshot(
                id: exchange.response.id.uuidString,
                statusCode: exchange.response.statusCode,
                headers: exchange.response.headers.map { PluginHeader(name: $0.0, value: $0.1) },
                bodyText: exchange.response.bodyString,
                raw: exchange.response.rawResponseText,
                displayText: exchange.response.fullResponseText,
                elapsedMilliseconds: exchange.response.elapsed * 1_000,
                size: exchange.response.size,
                error: exchange.response.error
            ),
            originPluginID: exchange.originPluginID,
            variantID: exchange.variantID,
            metadata: exchange.metadata
        )
    }

    private func apply(
        _ result: PluginEventResult,
        pluginID: String,
        exchanges: [RequestSender.SentExchange]
    ) {
        applyNonResponseResult(result, pluginID: pluginID)
        let responses = Dictionary(uniqueKeysWithValues: exchanges.map { ($0.response.id.uuidString, $0.response) })
        for annotation in result.annotations {
            guard let response = responses[annotation.responseID] else { continue }
            let ranges = locate(annotation: annotation, in: response)
            for (index, range) in ranges.enumerated() {
                annotations.append(
                    ResponseAnnotation(
                        id: "\(pluginID):\(annotation.id):\(index)",
                        responseID: response.id,
                        range: range,
                        severity: annotation.severity,
                        title: annotation.title,
                        message: annotation.message
                    )
                )
            }
        }
    }

    private func applyNonResponseResult(_ result: PluginEventResult, pluginID: String) {
        for finding in result.findings {
            findings.removeAll { $0.id == finding.id && $0.pluginID == pluginID }
            findings.append(
                PluginFinding(
                    id: finding.id,
                    pluginID: pluginID,
                    responseID: finding.responseID,
                    title: finding.title,
                    summary: finding.summary,
                    severity: finding.severity,
                    status: finding.status,
                    details: finding.details
                )
            )
        }
        if let message = result.statusMessage {
            statusMessages[pluginID] = message
        }
    }

    private func locate(annotation: PluginAnnotation, in response: HTTPResponse) -> [NSRange] {
        let text = response.fullResponseText as NSString
        if let location = annotation.location, let length = annotation.length {
            let range = NSRange(location: location, length: length)
            if NSIntersectionRange(range, NSRange(location: 0, length: text.length)).length == range.length {
                return [range]
            }
        }
        if let value = annotation.value, !value.isEmpty {
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let range = text.range(of: value, options: [], range: searchRange)
                guard range.location != NSNotFound else { break }
                ranges.append(range)
                let next = range.location + max(range.length, 1)
                searchRange = NSRange(location: next, length: max(0, text.length - next))
            }
            if !ranges.isEmpty { return ranges }
        }
        if let line = annotation.line, let indexed = response.lineIndex.line(at: line) {
            return [indexed.lineRange]
        }
        return []
    }

    private func pluginFailed(_ pluginID: String, error: Error) {
        updateStatus(pluginID: pluginID, status: .failed, diagnostic: error.localizedDescription)
        statusMessages[pluginID] = error.localizedDescription
    }

    private func updateStatus(pluginID: String, status: PluginStatus, diagnostic: String?) {
        guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else { return }
        plugins[index].status = status
        plugins[index].diagnostic = diagnostic
    }
}
