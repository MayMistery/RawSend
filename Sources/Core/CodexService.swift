import Foundation

struct CodexRunInput: Hashable {
    var userMessage: String
    var configuredUserPrompt: String
    var rawRequest: String
    var responseText: String
    var responseLabel: String
    var conversation: String
    var language: AppLanguage = .english
}

enum CodexServiceError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case failed(exitCode: Int32, output: String)
    case missingOutput
    case invalidOutput(String)

    var errorDescription: String? {
        localizedDescription(language: .simplifiedChinese)
    }

    func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .executableNotFound:
            return Localizer.text(.codexMissingCLI, language: language)
        case .launchFailed(let message):
            return Localizer.format(.codexLaunchFailed, language: language, message)
        case .failed(let exitCode, let output):
            return Localizer.format(.codexExecutionFailed, language: language, exitCode, output)
        case .missingOutput:
            return Localizer.text(.codexNoStructuredOutput, language: language)
        case .invalidOutput(let output):
            return Localizer.format(.codexParseFailed, language: language, output)
        }
    }
}

final class CodexService {
    func run(input: CodexRunInput) async throws -> CodexRunResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runBlocking(input: input)
        }.value
    }

    private static func runBlocking(input: CodexRunInput) throws -> CodexRunResult {
        guard let executable = findCodexExecutable() else {
            throw CodexServiceError.executableNotFound
        }

        let fileManager = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RawSendCodex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let schemaURL = tempRoot.appendingPathComponent("schema.json")
        let outputURL = tempRoot.appendingPathComponent("result.json")
        let stdoutURL = tempRoot.appendingPathComponent("stdout.jsonl")
        let stderrURL = tempRoot.appendingPathComponent("stderr.txt")
        try CodexPrompt.outputSchema.write(to: schemaURL, atomically: true, encoding: .utf8)
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = tempRoot
        process.arguments = [
            "exec",
            "--json",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--output-schema",
            schemaURL.path,
            "-o",
            outputURL.path,
            "-",
        ]

        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw CodexServiceError.launchFailed(error.localizedDescription)
        }

        let prompt = CodexPrompt.makePrompt(input: input)
        if let data = prompt.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdout = readString(stdoutURL)
        let stderr = readString(stderrURL)
        if process.terminationStatus != 0 {
            let output = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw CodexServiceError.failed(exitCode: process.terminationStatus, output: output)
        }

        guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
            throw CodexServiceError.missingOutput
        }

        do {
            return try JSONDecoder().decode(CodexRunResult.self, from: data)
        } catch {
            let output = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            throw CodexServiceError.invalidOutput(output)
        }
    }

    private static func findCodexExecutable() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let explicit = ProcessInfo.processInfo.environment["RAWSEND_CODEX_PATH"] {
            candidates.append(explicit)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path
                .split(separator: ":")
                .map { String($0) + "/codex" })
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex",
        ])

        return candidates.first {
            fileManager.isExecutableFile(atPath: $0)
        }
    }

    private static func readString(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
