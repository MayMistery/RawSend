import Foundation
import Testing
@testable import RawSend

private actor HostCallRecorder {
    private(set) var methods: [String] = []

    func handle(_ method: String, params: JSONValue?) -> Result<JSONValue, PluginRuntimeError> {
        methods.append(method)
        switch method {
        case "host.info":
            return .success(.object(["name": .string("RawSend")]))
        case "ui.status.set":
            return .success(.bool(true))
        default:
            return .failure(.protocolFailure("unsupported"))
        }
    }
}

@Suite("External plugin system")
struct PluginSystemTests {
    private var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    @Test func manifestLoadsExternalPythonPlugin() throws {
        let loaded = try PluginManifestLoader.load(
            bundleURL: fixturesURL.appendingPathComponent("Echo.rawsendplugin")
        )
        #expect(loaded.manifest.id == "com.rawsend.tests.echo")
        #expect(loaded.manifest.runtime.kind == .python)
        #expect(loaded.entrypointURL.lastPathComponent == "main.py")
    }

    @Test func manifestRejectsEntrypointTraversal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Bad.rawsendplugin")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            manifestVersion: 1,
            id: "com.rawsend.tests.bad",
            name: "Bad",
            version: "1",
            hostAPI: .init(major: 1, minor: 0),
            runtime: .init(kind: .process, entrypoint: "../escape", interpreter: nil, arguments: nil, architectures: nil),
            hooks: [],
            permissions: []
        )
        try JSONEncoder().encode(manifest).write(to: bundle.appendingPathComponent("plugin.json"))

        do {
            _ = try PluginManifestLoader.load(bundleURL: bundle)
            Issue.record("Traversal manifest unexpectedly loaded")
        } catch let error as PluginManifestError {
            #expect(error == .invalidEntrypoint)
        }
    }

    @Test func framedRPCHandlesMultilineJSON() throws {
        let message = PluginRPCMessage.request(
            id: 7,
            method: "test",
            params: .object(["value": .string("line one\nline two")])
        )
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: PluginRPCFraming.frame(message))
        try pipe.fileHandleForWriting.close()
        let decoded = try PluginRPCFrameReader(handle: pipe.fileHandleForReading).readMessage()
        #expect(decoded == message)
    }

    @Test func requestFieldsMutateQueryFormAndJSON() throws {
        let queryRequest = HTTPRequest(
            method: "GET",
            host: "example.com",
            path: "/fetch?a=1&url=http%3A%2F%2Fold.example%2F",
            headers: []
        )
        let queryField = try #require(
            RequestFieldExtractor.fields(in: queryRequest).first { $0.name == "url" }
        )
        let queryMutated = try RequestFieldExtractor.applying(
            PluginMutation(targetID: queryField.id, replacement: "http://callback.test/a"),
            to: queryRequest
        )
        #expect(queryMutated.path.contains("url=http%3A%2F%2Fcallback.test%2Fa"))

        let formRequest = HTTPRequest(
            method: "POST",
            host: "example.com",
            path: "/fetch",
            headers: [("Content-Type", "application/x-www-form-urlencoded")],
            body: "url=http%3A%2F%2Fold.example%2F&x=1"
        )
        let formField = try #require(RequestFieldExtractor.fields(in: formRequest).first)
        let formMutated = try RequestFieldExtractor.applying(
            PluginMutation(targetID: formField.id, replacement: "http://callback.test/form"),
            to: formRequest
        )
        #expect(formMutated.body.contains("http%3A%2F%2Fcallback.test%2Fform"))
        #expect(formMutated.headers.contains {
            $0.0 == "Content-Length" && $0.1 == String(formMutated.body.lengthOfBytes(using: .utf8))
        })

        let jsonRequest = HTTPRequest(
            method: "POST",
            host: "example.com",
            path: "/fetch",
            headers: [("Content-Type", "application/json")],
            body: #"{"nested":{"url":"http://old.example/"}}"#
        )
        let jsonField = try #require(RequestFieldExtractor.fields(in: jsonRequest).first)
        let jsonMutated = try RequestFieldExtractor.applying(
            PluginMutation(targetID: jsonField.id, replacement: "http://callback.test/json"),
            to: jsonRequest
        )
        #expect(jsonMutated.body.contains("http:\\/\\/callback.test\\/json") || jsonMutated.body.contains("http://callback.test/json"))
    }

    @Test func processRuntimeSupportsHooksAndBidirectionalHostCalls() async throws {
        let loaded = try PluginManifestLoader.load(
            bundleURL: fixturesURL.appendingPathComponent("Echo.rawsendplugin")
        )
        let recorder = HostCallRecorder()
        let runtime = ProcessPluginRuntime(loaded: loaded) { method, params in
            await recorder.handle(method, params: params)
        }
        try await runtime.start(initialize: initializeParams(loaded))
        let request = HTTPRequest(
            method: "GET",
            host: "example.com",
            path: "/?url=http://old.example/",
            headers: []
        )
        let params = PluginSendPlanParams(
            request: snapshot(request),
            schemes: ["http"],
            settings: [:]
        )
        let value = try await runtime.call(
            method: "send.plan",
            params: try JSONValue.fromEncodable(params),
            timeout: 5
        )
        let result = try value.decode(PluginEventResult.self)
        #expect(result.variants.count == 1)
        #expect(result.variants[0].mutations[0].replacement == "http://callback.fixture/")
        let methods = await recorder.methods
        #expect(methods.contains("host.info"))
        #expect(methods.contains("ui.status.set"))
        await runtime.stop()
    }

    @Test func nativeRuntimeLoadsCABIPlugin() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Native.rawsendplugin")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let dylib = bundle.appendingPathComponent("plugin.dylib")
        try runProcess(
            executable: "/usr/bin/clang",
            arguments: [
                "-dynamiclib",
                fixturesURL.appendingPathComponent("native_echo_plugin.c").path,
                "-o",
                dylib.path,
            ]
        )
        let manifest = PluginManifest(
            manifestVersion: 1,
            id: "com.rawsend.tests.native",
            name: "Native Test",
            version: "1.0.0",
            hostAPI: .init(major: 1, minor: 0),
            runtime: .init(kind: .native, entrypoint: "plugin.dylib", interpreter: nil, arguments: nil, architectures: nil),
            hooks: ["exchange.completed"],
            permissions: []
        )
        try JSONEncoder().encode(manifest).write(to: bundle.appendingPathComponent("plugin.json"))
        let loaded = try PluginManifestLoader.load(bundleURL: bundle)
        let runtime = NativePluginRuntime(loaded: loaded)
        try await runtime.start(initialize: initializeParams(loaded))
        let value = try await runtime.call(
            method: "exchange.completed",
            params: .object([:]),
            timeout: 5
        )
        let result = try value.decode(PluginEventResult.self)
        #expect(result.statusMessage == "native-ok")
        await runtime.stop()
        try await runtime.start(initialize: initializeParams(loaded))
        let restartedValue = try await runtime.call(
            method: "exchange.completed",
            params: .object([:]),
            timeout: 5
        )
        let restartedResult = try restartedValue.decode(PluginEventResult.self)
        #expect(restartedResult.statusMessage == "native-ok")
        await runtime.stop()
    }

    @MainActor
    @Test func fullProcessPluginRequestResponseFlow() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = root.appendingPathComponent("Plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixturesURL.appendingPathComponent("Echo.rawsendplugin"),
            to: pluginDirectory.appendingPathComponent("Echo.rawsendplugin")
        )

        let server = try startMockServer(requestCount: 2)
        defer {
            if server.process.isRunning { server.process.terminate() }
        }

        let manager = PluginManager(
            discoveryDirectories: [pluginDirectory],
            persistence: PersistenceManager(baseURL: root.appendingPathComponent("State"))
        )
        await manager.reload()
        #expect(manager.plugins.first?.status == .running)

        let sender = RequestSender()
        let raw = """
        GET /fetch?url=http%3A%2F%2Fold.example%2F HTTP/1.1
        Host: 127.0.0.1:\(server.port)

        """
        let prepared = try #require(await sender.prepare(
            rawText: raw,
            environment: nil,
            defaultHeaders: []
        ))
        let plans = await manager.prepareSend(request: prepared, schemes: ["http"])
        #expect(plans.count == 1)

        let baseline = await sender.sendPrepared(
            prepared,
            schemes: ["http"],
            preferences: AppPreferences()
        )
        let mutated = try RequestFieldExtractor.applying(
            plans[0].variant.mutations,
            to: prepared
        )
        let variants = await sender.sendPrepared(
            mutated,
            schemes: ["http"],
            preferences: AppPreferences(),
            originPluginID: plans[0].pluginID,
            variantID: plans[0].variant.id,
            metadata: plans[0].variant.metadata
        )
        await manager.analyze(exchanges: baseline)
        #expect(manager.findings.contains { $0.title == "Fixture finding" })
        #expect(!manager.annotations(for: baseline[0].response.id).isEmpty)
        #expect(variants[0].request.path.contains("callback.fixture"))
        await manager.shutdown()
        server.process.waitUntilExit()
        #expect(server.process.terminationStatus == 0)
    }

    private func initializeParams(_ loaded: LoadedPluginManifest) -> PluginInitializeParams {
        PluginInitializeParams(
            host: .init(
                name: "RawSend",
                version: "test",
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

    private func snapshot(_ request: HTTPRequest) -> PluginRequestSnapshot {
        PluginRequestSnapshot(
            method: request.method,
            scheme: nil,
            host: request.host,
            path: request.path,
            headers: request.headers.map { PluginHeader(name: $0.0, value: $0.1) },
            body: request.body,
            raw: RequestParser.buildRaw(from: request),
            fields: RequestFieldExtractor.fields(in: request)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawsend-plugin-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PluginRuntimeError.launchFailed(message)
        }
    }

    private func startMockServer(requestCount: Int) throws -> (process: Process, port: Int) {
        let python = try #require(InterpreterResolver.resolve("python3"))
        let process = Process()
        let stdout = Pipe()
        process.executableURL = python
        process.arguments = [
            fixturesURL.appendingPathComponent("mock_http_server.py").path,
            String(requestCount),
        ]
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let port = try #require(Int(output.trimmingCharacters(in: .whitespacesAndNewlines)))
        return (process, port)
    }
}
