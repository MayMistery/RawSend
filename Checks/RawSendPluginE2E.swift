import Foundation

private actor CheckHostCallRecorder {
    private(set) var methods: [String] = []

    func handle(_ method: String) -> Result<JSONValue, PluginRuntimeError> {
        methods.append(method)
        switch method {
        case "host.info":
            return .success(.object(["name": .string("RawSend")]))
        case "ui.status.set":
            return .success(.bool(true))
        default:
            return .failure(.protocolFailure("unsupported host call"))
        }
    }
}

@main
struct RawSendPluginE2E {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtures = root
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
        let echoBundle = fixtures.appendingPathComponent("Echo.rawsendplugin")

        let loaded = try PluginManifestLoader.load(bundleURL: echoBundle)
        try expect(loaded.manifest.id == "com.rawsend.tests.echo", "manifest discovery")

        let request = HTTPRequest(
            method: "GET",
            host: "example.com",
            path: "/fetch?url=http%3A%2F%2Fold.example%2F",
            headers: []
        )
        let field = try require(RequestFieldExtractor.fields(in: request).first)
        let mutated = try RequestFieldExtractor.applying(
            PluginMutation(targetID: field.id, replacement: "http://callback.check/"),
            to: request
        )
        try expect(mutated.path.contains("callback.check"), "declarative request mutation")

        let recorder = CheckHostCallRecorder()
        let processRuntime = ProcessPluginRuntime(loaded: loaded) { method, _ in
            await recorder.handle(method)
        }
        try await processRuntime.start(initialize: initializeParams(loaded))
        let planValue = try await processRuntime.call(
            method: "send.plan",
            params: try JSONValue.fromEncodable(
                PluginSendPlanParams(
                    request: snapshot(request),
                    schemes: ["http"],
                    settings: [:]
                )
            ),
            timeout: 5
        )
        let plan = try planValue.decode(PluginEventResult.self)
        try expect(plan.variants.count == 1, "process plugin hook")
        let hostMethods = await recorder.methods
        try expect(hostMethods.contains("host.info") && hostMethods.contains("ui.status.set"), "bidirectional Host API")
        await processRuntime.stop()

        let goExecutable = try require(InterpreterResolver.resolve("go"))
        let goProcessRoot = try temporaryDirectory(prefix: "rawsend-go-process-check")
        defer { try? FileManager.default.removeItem(at: goProcessRoot) }
        let goProcessBundle = goProcessRoot.appendingPathComponent("GoProcess.rawsendplugin")
        try FileManager.default.createDirectory(at: goProcessBundle, withIntermediateDirectories: true)
        let goProcessEntrypoint = goProcessBundle.appendingPathComponent("plugin")
        try run(
            executable: goExecutable.path,
            arguments: ["build", "-o", goProcessEntrypoint.path, "."],
            currentDirectoryURL: fixtures.appendingPathComponent("GoEchoPlugin")
        )
        let goProcessManifest = PluginManifest(
            manifestVersion: 1,
            id: "com.rawsend.check.go-process",
            name: "Go Process Check",
            version: "1.0.0",
            hostAPI: .init(major: 1, minor: 0),
            runtime: .init(
                kind: .process,
                entrypoint: "plugin",
                interpreter: nil,
                arguments: nil,
                architectures: nil
            ),
            hooks: ["exchange.completed"],
            permissions: ["ui.status.write"]
        )
        try JSONEncoder().encode(goProcessManifest).write(
            to: goProcessBundle.appendingPathComponent("plugin.json")
        )
        let goProcessLoaded = try PluginManifestLoader.load(bundleURL: goProcessBundle)
        let goProcessRecorder = CheckHostCallRecorder()
        let goProcessRuntime = ProcessPluginRuntime(loaded: goProcessLoaded) { method, _ in
            await goProcessRecorder.handle(method)
        }
        try await goProcessRuntime.start(initialize: initializeParams(goProcessLoaded))
        let goProcessValue = try await goProcessRuntime.call(
            method: "exchange.completed",
            params: .object([:]),
            timeout: 5
        )
        let goProcessResult = try goProcessValue.decode(PluginEventResult.self)
        try expect(goProcessResult.statusMessage == "go-process-ok", "Go process plugin")
        let goHostMethods = await goProcessRecorder.methods
        try expect(
            goHostMethods.contains("host.info") && goHostMethods.contains("ui.status.set"),
            "Go process Host API"
        )
        await goProcessRuntime.stop()

        let nativeRoot = try temporaryDirectory(prefix: "rawsend-native-check")
        defer { try? FileManager.default.removeItem(at: nativeRoot) }
        let nativeBundle = nativeRoot.appendingPathComponent("Native.rawsendplugin")
        try FileManager.default.createDirectory(at: nativeBundle, withIntermediateDirectories: true)
        let dylib = nativeBundle.appendingPathComponent("plugin.dylib")
        try run(
            executable: "/usr/bin/clang",
            arguments: [
                "-dynamiclib",
                fixtures.appendingPathComponent("native_echo_plugin.c").path,
                "-o",
                dylib.path,
            ]
        )
        let nativeManifest = PluginManifest(
            manifestVersion: 1,
            id: "com.rawsend.check.native",
            name: "Native Check",
            version: "1.0.0",
            hostAPI: .init(major: 1, minor: 0),
            runtime: .init(
                kind: .native,
                entrypoint: "plugin.dylib",
                interpreter: nil,
                arguments: nil,
                architectures: nil
            ),
            hooks: ["exchange.completed"],
            permissions: []
        )
        try JSONEncoder().encode(nativeManifest).write(to: nativeBundle.appendingPathComponent("plugin.json"))
        let nativeLoaded = try PluginManifestLoader.load(bundleURL: nativeBundle)
        let nativeRuntime = NativePluginRuntime(loaded: nativeLoaded)
        try await nativeRuntime.start(initialize: initializeParams(nativeLoaded))
        let nativeValue = try await nativeRuntime.call(
            method: "exchange.completed",
            params: .object([:]),
            timeout: 5
        )
        let nativeResult = try nativeValue.decode(PluginEventResult.self)
        try expect(nativeResult.statusMessage == "native-ok", "native dylib ABI")
        await nativeRuntime.stop()
        try await nativeRuntime.start(initialize: initializeParams(nativeLoaded))
        let restartedNativeValue = try await nativeRuntime.call(
            method: "exchange.completed",
            params: .object([:]),
            timeout: 5
        )
        let restartedNativeResult = try restartedNativeValue.decode(PluginEventResult.self)
        try expect(restartedNativeResult.statusMessage == "native-ok", "native dylib restart")
        await nativeRuntime.stop()

        let goNativeRoot = try temporaryDirectory(prefix: "rawsend-go-native-check")
        defer { try? FileManager.default.removeItem(at: goNativeRoot) }
        let goNativeBundle = goNativeRoot.appendingPathComponent("GoNative.rawsendplugin")
        try FileManager.default.createDirectory(at: goNativeBundle, withIntermediateDirectories: true)
        let goNativeDylib = goNativeBundle.appendingPathComponent("plugin.dylib")
        try run(
            executable: goExecutable.path,
            arguments: ["build", "-buildmode=c-shared", "-o", goNativeDylib.path, "."],
            currentDirectoryURL: fixtures.appendingPathComponent("GoNativePlugin")
        )
        let goNativeManifest = PluginManifest(
            manifestVersion: 1,
            id: "com.rawsend.check.go-native",
            name: "Go Native Check",
            version: "1.0.0",
            hostAPI: .init(major: 1, minor: 0),
            runtime: .init(
                kind: .native,
                entrypoint: "plugin.dylib",
                interpreter: nil,
                arguments: nil,
                architectures: nil
            ),
            hooks: ["exchange.completed"],
            permissions: []
        )
        try JSONEncoder().encode(goNativeManifest).write(
            to: goNativeBundle.appendingPathComponent("plugin.json")
        )
        let goNativeLoaded = try PluginManifestLoader.load(bundleURL: goNativeBundle)
        let goNativeRuntime = NativePluginRuntime(loaded: goNativeLoaded)
        try await goNativeRuntime.start(initialize: initializeParams(goNativeLoaded))
        let goNativeValue = try await goNativeRuntime.call(
            method: "exchange.completed",
            params: .object([:]),
            timeout: 5
        )
        let goNativeResult = try goNativeValue.decode(PluginEventResult.self)
        try expect(goNativeResult.statusMessage == "go-native-ok", "Go c-shared dylib")
        await goNativeRuntime.stop()

        let integrationRoot = try temporaryDirectory(prefix: "rawsend-manager-check")
        defer { try? FileManager.default.removeItem(at: integrationRoot) }
        let pluginDirectory = integrationRoot.appendingPathComponent("Plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: echoBundle,
            to: pluginDirectory.appendingPathComponent("Echo.rawsendplugin")
        )
        let server = try startMockServer(fixtures: fixtures, requestCount: 2)
        defer {
            if server.process.isRunning { server.process.terminate() }
        }

        let manager = PluginManager(
            discoveryDirectories: [pluginDirectory],
            persistence: PersistenceManager(baseURL: integrationRoot.appendingPathComponent("State"))
        )
        await manager.reload()
        try expect(manager.plugins.first?.status == .running, "plugin manager lifecycle")
        let sender = RequestSender()
        let raw = """
        GET /fetch?url=http%3A%2F%2Fold.example%2F HTTP/1.1
        Host: 127.0.0.1:\(server.port)

        """
        let prepared = try require(await sender.prepare(
            rawText: raw,
            environment: nil,
            defaultHeaders: []
        ))
        let planned = await manager.prepareSend(request: prepared, schemes: ["http"])
        try expect(planned.count == 1, "send plan integration")
        let baseline = await sender.sendPrepared(
            prepared,
            schemes: ["http"],
            preferences: AppPreferences()
        )
        let variantRequest = try RequestFieldExtractor.applying(
            planned[0].variant.mutations,
            to: prepared
        )
        let variantExchanges = await sender.sendPrepared(
            variantRequest,
            schemes: ["http"],
            preferences: AppPreferences(),
            originPluginID: planned[0].pluginID,
            variantID: planned[0].variant.id,
            metadata: planned[0].variant.metadata
        )
        await manager.analyze(exchanges: baseline)
        try expect(manager.findings.contains { $0.title == "Fixture finding" }, "response finding integration")
        try expect(!manager.annotations(for: baseline[0].response.id).isEmpty, "response annotation integration")
        try expect(variantExchanges[0].request.path.contains("callback.fixture"), "variant transport integration")
        await manager.shutdown()
        server.process.waitUntilExit()
        try expect(server.process.terminationStatus == 0, "mock target completed")

        print("RawSend plugin E2E checks passed")
        print("- external manifest discovery: PASS")
        print("- Python/Go process JSON-RPC + Host API: PASS")
        print("- C/Go native dylib ABI + restart: PASS")
        print("- request mutation + transport: PASS")
        print("- response finding + exact annotation: PASS")
    }

    private static func initializeParams(_ loaded: LoadedPluginManifest) -> PluginInitializeParams {
        PluginInitializeParams(
            host: .init(
                name: "RawSend",
                version: "check",
                api: PluginManifest.hostAPI,
                platform: "macOS",
                architecture: PluginPlatform.architecture
            ),
            plugin: loaded.manifest,
            bundlePath: loaded.bundleURL.path,
            grantedPermissions: loaded.manifest.permissions,
            settings: loaded.manifest.settings ?? [:]
        )
    }

    private static func snapshot(_ request: HTTPRequest) -> PluginRequestSnapshot {
        PluginRequestSnapshot(
            method: request.method,
            scheme: nil,
            host: request.host,
            path: request.path,
            headers: request.headers.map { .init(name: $0.0, value: $0.1) },
            body: request.body,
            raw: RequestParser.buildRaw(from: request),
            fields: RequestFieldExtractor.fields(in: request)
        )
    }

    private static func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw PluginRuntimeError.launchFailed(message)
        }
    }

    private static func startMockServer(
        fixtures: URL,
        requestCount: Int
    ) throws -> (process: Process, port: Int) {
        let python = try require(InterpreterResolver.resolve("python3"))
        let process = Process()
        let stdout = Pipe()
        process.executableURL = python
        process.arguments = [
            fixtures.appendingPathComponent("mock_http_server.py").path,
            String(requestCount),
        ]
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let output = String(data: stdout.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        let port = try require(Int(output.trimmingCharacters(in: .whitespacesAndNewlines)))
        return (process, port)
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw PluginRuntimeError.protocolFailure("Required E2E value is missing")
        }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else {
            throw PluginRuntimeError.protocolFailure("E2E assertion failed: \(label)")
        }
    }
}
