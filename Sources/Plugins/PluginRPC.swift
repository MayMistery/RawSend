import Foundation

struct PluginRPCErrorPayload: Codable, Equatable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?
}

struct PluginRPCMessage: Codable, Equatable, Sendable {
    var jsonrpc: String = "2.0"
    var id: Int?
    var method: String?
    var params: JSONValue?
    var result: JSONValue?
    var error: PluginRPCErrorPayload?

    static func request(id: Int, method: String, params: JSONValue?) -> PluginRPCMessage {
        PluginRPCMessage(id: id, method: method, params: params)
    }

    static func response(id: Int, result: JSONValue) -> PluginRPCMessage {
        PluginRPCMessage(id: id, result: result)
    }

    static func failure(id: Int, code: Int, message: String) -> PluginRPCMessage {
        PluginRPCMessage(id: id, error: PluginRPCErrorPayload(code: code, message: message, data: nil))
    }
}

enum PluginRPCFramingError: LocalizedError {
    case endOfFile
    case malformedHeader
    case invalidLength
    case oversizedMessage

    var errorDescription: String? {
        switch self {
        case .endOfFile: return "Plugin process closed its output"
        case .malformedHeader: return "Malformed plugin RPC header"
        case .invalidLength: return "Invalid plugin RPC Content-Length"
        case .oversizedMessage: return "Plugin RPC message exceeds the maximum size"
        }
    }
}

struct PluginRPCFraming {
    static let maximumMessageBytes = 16 * 1024 * 1024

    static func frame(_ message: PluginRPCMessage) throws -> Data {
        let body = try JSONEncoder().encode(message)
        guard body.count <= maximumMessageBytes else {
            throw PluginRPCFramingError.oversizedMessage
        }
        var data = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        data.append(body)
        return data
    }
}

final class PluginRPCFrameReader {
    private var buffer = Data()
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readMessage() throws -> PluginRPCMessage {
        let separator = Data("\r\n\r\n".utf8)
        while true {
            if let headerRange = buffer.range(of: separator) {
                let headerData = buffer[..<headerRange.lowerBound]
                guard let header = String(data: headerData, encoding: .utf8) else {
                    throw PluginRPCFramingError.malformedHeader
                }
                let lengthLine = header.components(separatedBy: "\r\n").first {
                    $0.lowercased().hasPrefix("content-length:")
                }
                guard let lengthLine,
                      let length = Int(lengthLine.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)),
                      length >= 0 else {
                    throw PluginRPCFramingError.invalidLength
                }
                guard length <= PluginRPCFraming.maximumMessageBytes else {
                    throw PluginRPCFramingError.oversizedMessage
                }
                let bodyStart = headerRange.upperBound
                let required = bodyStart + length
                if buffer.count >= required {
                    let body = buffer.subdata(in: bodyStart..<required)
                    buffer.removeSubrange(0..<required)
                    return try JSONDecoder().decode(PluginRPCMessage.self, from: body)
                }
            }

            let next = handle.availableData
            guard !next.isEmpty else { throw PluginRPCFramingError.endOfFile }
            buffer.append(next)
            guard buffer.count <= PluginRPCFraming.maximumMessageBytes + 64 * 1024 else {
                throw PluginRPCFramingError.oversizedMessage
            }
        }
    }
}

enum PluginRuntimeError: LocalizedError, Equatable {
    case notStarted
    case launchFailed(String)
    case protocolFailure(String)
    case remoteError(Int, String)
    case timedOut(String)
    case terminated(String)
    case incompatibleNativeAPI(Int)
    case missingNativeSymbol(String)
    case nativeCallFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notStarted: return "Plugin runtime is not started"
        case let .launchFailed(message): return "Failed to launch plugin: \(message)"
        case let .protocolFailure(message): return "Plugin protocol failure: \(message)"
        case let .remoteError(code, message): return "Plugin error \(code): \(message)"
        case let .timedOut(method): return "Plugin call timed out: \(method)"
        case let .terminated(message): return "Plugin terminated: \(message)"
        case let .incompatibleNativeAPI(version): return "Native plugin ABI is incompatible: \(version)"
        case let .missingNativeSymbol(symbol): return "Native plugin symbol is missing: \(symbol)"
        case let .nativeCallFailed(code): return "Native plugin call failed with code \(code)"
        }
    }
}

typealias PluginHostCallHandler = @Sendable (String, JSONValue?) async -> Result<JSONValue, PluginRuntimeError>

protocol PluginRuntimeClient: AnyObject {
    func start(initialize: PluginInitializeParams) async throws
    func call(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue
    func stop() async
}
