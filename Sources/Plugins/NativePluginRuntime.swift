import Foundation
import Darwin

actor NativePluginRuntime: PluginRuntimeClient {
    private typealias VersionFunction = @convention(c) () -> UInt32
    private typealias HandleFunction = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
    ) -> Int32
    private typealias FreeFunction = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void
    private typealias ShutdownFunction = @convention(c) () -> Void

    private let loaded: LoadedPluginManifest
    private var handle: UnsafeMutableRawPointer?
    private var handleFunction: HandleFunction?
    private var freeFunction: FreeFunction?
    private var shutdownFunction: ShutdownFunction?
    private var nextID = 1
    private var isStarted = false

    init(loaded: LoadedPluginManifest) {
        self.loaded = loaded
    }

    func start(initialize: PluginInitializeParams) async throws {
        guard !isStarted else { return }
        let openedNewImage = handle == nil
        let activeHandle: UnsafeMutableRawPointer
        if let handle {
            activeHandle = handle
        } else {
            guard let opened = dlopen(loaded.entrypointURL.path, RTLD_NOW | RTLD_LOCAL) else {
                let message = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
                throw PluginRuntimeError.launchFailed(message)
            }
            activeHandle = opened
        }
        do {
            if handleFunction == nil || freeFunction == nil {
                let version: VersionFunction = try symbol(
                    "rawsend_plugin_api_version_v1",
                    handle: activeHandle
                )
                let apiVersion = Int(version() >> 16)
                guard apiVersion == PluginManifest.hostAPI.major else {
                    throw PluginRuntimeError.incompatibleNativeAPI(apiVersion)
                }
                handleFunction = try symbol("rawsend_plugin_handle_v1", handle: activeHandle)
                freeFunction = try symbol("rawsend_plugin_free_v1", handle: activeHandle)
                shutdownFunction = optionalSymbol("rawsend_plugin_shutdown_v1", handle: activeHandle)
            }
            handle = activeHandle
            isStarted = true
            _ = try await call(
                method: "initialize",
                params: try JSONValue.fromEncodable(initialize),
                timeout: 10
            )
        } catch {
            isStarted = false
            if openedNewImage {
                handle = nil
                handleFunction = nil
                freeFunction = nil
                shutdownFunction = nil
                dlclose(activeHandle)
            }
            throw error
        }
    }

    func call(method: String, params: JSONValue?, timeout: TimeInterval = 30) async throws -> JSONValue {
        guard isStarted, let handleFunction, let freeFunction else {
            throw PluginRuntimeError.notStarted
        }
        let id = nextID
        nextID += 1
        let request = PluginRPCMessage.request(id: id, method: method, params: params)
        let input = try JSONEncoder().encode(request)
        var outputPointer: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = input.withUnsafeBytes { rawBuffer -> Int32 in
            handleFunction(
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                input.count,
                &outputPointer,
                &outputLength
            )
        }
        guard status == 0 else { throw PluginRuntimeError.nativeCallFailed(Int(status)) }
        guard let outputPointer, outputLength >= 0 else {
            throw PluginRuntimeError.protocolFailure("Native plugin returned no response")
        }
        defer { freeFunction(outputPointer, outputLength) }
        let output = Data(bytes: outputPointer, count: outputLength)
        let response = try JSONDecoder().decode(PluginRPCMessage.self, from: output)
        guard response.id == id else {
            throw PluginRuntimeError.protocolFailure("Native plugin response id mismatch")
        }
        if let error = response.error {
            throw PluginRuntimeError.remoteError(error.code, error.message)
        }
        return response.result ?? .null
    }

    func stop() async {
        guard isStarted else { return }
        shutdownFunction?()
        // Native runtimes, especially Go c-shared, may own background threads.
        // Keep the image loaded until process exit and only disable dispatch.
        isStarted = false
    }

    private func symbol<T>(_ name: String, handle: UnsafeMutableRawPointer) throws -> T {
        guard let raw = dlsym(handle, name) else {
            throw PluginRuntimeError.missingNativeSymbol(name)
        }
        return unsafeBitCast(raw, to: T.self)
    }

    private func optionalSymbol<T>(_ name: String, handle: UnsafeMutableRawPointer) -> T? {
        guard let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
