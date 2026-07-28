import Foundation

actor ProcessPluginRuntime: PluginRuntimeClient {
    private let loaded: LoadedPluginManifest
    private let hostCallHandler: PluginHostCallHandler
    private var process: Process?
    private var inputHandle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var stderrTail = Data()
    private let stderrLimit = 32 * 1024

    init(loaded: LoadedPluginManifest, hostCallHandler: @escaping PluginHostCallHandler) {
        self.loaded = loaded
        self.hostCallHandler = hostCallHandler
    }

    func start(initialize: PluginInitializeParams) async throws {
        guard process == nil else { return }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        do {
            let command = try resolveCommand()
            process.executableURL = command.executable
            process.arguments = command.arguments
            process.currentDirectoryURL = loaded.bundleURL
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["RAWSEND_PLUGIN_BUNDLE"] = loaded.bundleURL.path
            process.environment = environment
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { [weak self] process in
                Task {
                    await self?.processTerminated(
                        "exit=\(process.terminationStatus), reason=\(process.terminationReason.rawValue)"
                    )
                }
            }
            try process.run()
        } catch {
            throw PluginRuntimeError.launchFailed(error.localizedDescription)
        }

        self.process = process
        inputHandle = stdin.fileHandleForWriting
        let outputHandle = stdout.fileHandleForReading
        let errorHandle = stderr.fileHandleForReading

        readerTask = Task.detached(priority: .utility) { [weak self] in
            let reader = PluginRPCFrameReader(handle: outputHandle)
            do {
                while !Task.isCancelled {
                    let message = try reader.readMessage()
                    await self?.receive(message)
                }
            } catch {
                await self?.readerFailed(error.localizedDescription)
            }
        }
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let data = errorHandle.availableData
                if data.isEmpty { break }
                await self?.appendStderr(data)
            }
        }

        do {
            _ = try await call(
                method: "initialize",
                params: try JSONValue.fromEncodable(initialize),
                timeout: 10
            )
        } catch {
            await stop()
            throw error
        }
    }

    func call(method: String, params: JSONValue?, timeout: TimeInterval = 30) async throws -> JSONValue {
        guard let process, process.isRunning, let inputHandle else {
            throw PluginRuntimeError.notStarted
        }
        let id = nextID
        nextID += 1
        let frame = try PluginRPCFraming.frame(.request(id: id, method: method, params: params))
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try inputHandle.write(contentsOf: frame)
                timeoutTasks[id] = Task { [weak self] in
                    let nanoseconds = UInt64(max(0.1, timeout) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    await self?.timeout(id: id, method: method)
                }
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: PluginRuntimeError.protocolFailure(error.localizedDescription))
            }
        }
    }

    func stop() async {
        readerTask?.cancel()
        stderrTask?.cancel()
        readerTask = nil
        stderrTask = nil
        for task in timeoutTasks.values { task.cancel() }
        timeoutTasks.removeAll()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        inputHandle = nil
        failAll(PluginRuntimeError.terminated("stopped"))
    }

    private func receive(_ message: PluginRPCMessage) async {
        if let id = message.id, message.method == nil {
            timeoutTasks.removeValue(forKey: id)?.cancel()
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if let error = message.error {
                continuation.resume(throwing: PluginRuntimeError.remoteError(error.code, error.message))
            } else {
                continuation.resume(returning: message.result ?? .null)
            }
            return
        }

        if let id = message.id, let method = message.method {
            let result = await hostCallHandler(method, message.params)
            let response: PluginRPCMessage
            switch result {
            case let .success(value):
                response = .response(id: id, result: value)
            case let .failure(error):
                response = .failure(id: id, code: -32000, message: error.localizedDescription)
            }
            do {
                try inputHandle?.write(contentsOf: PluginRPCFraming.frame(response))
            } catch {
                readerFailed(error.localizedDescription)
            }
        }
    }

    private func timeout(id: Int, method: String) {
        timeoutTasks.removeValue(forKey: id)
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: PluginRuntimeError.timedOut(method))
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func readerFailed(_ message: String) {
        let stderr = String(data: stderrTail, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = stderr.isEmpty ? "" : " stderr: \(stderr)"
        failAll(PluginRuntimeError.protocolFailure(message + suffix))
    }

    private func processTerminated(_ message: String) {
        process = nil
        failAll(PluginRuntimeError.terminated(message))
    }

    private func failAll(_ error: PluginRuntimeError) {
        let continuations = pending.values
        pending.removeAll()
        for task in timeoutTasks.values { task.cancel() }
        timeoutTasks.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func appendStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > stderrLimit {
            stderrTail.removeFirst(stderrTail.count - stderrLimit)
        }
    }

    private func resolveCommand() throws -> (executable: URL, arguments: [String]) {
        let runtime = loaded.manifest.runtime
        switch runtime.kind {
        case .process:
            return (loaded.entrypointURL, runtime.arguments ?? [])
        case .python:
            guard let executable = InterpreterResolver.resolve(runtime.interpreter ?? "python3") else {
                throw PluginRuntimeError.launchFailed("Python interpreter not found")
            }
            return (executable, [loaded.entrypointURL.path] + (runtime.arguments ?? []))
        case .native:
            throw PluginRuntimeError.launchFailed("Native plugins require NativePluginRuntime")
        }
    }
}

enum InterpreterResolver {
    static func resolve(_ command: String) -> URL? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command)
                ? URL(fileURLWithPath: command)
                : nil
        }
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        directories.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
