import Foundation

/// Raw HTTP 报文解析器
struct RequestParser {

    /// 从 raw text 解析出 HTTPRequest
    static func parse(_ rawText: String) -> HTTPRequest? {
        let parts = splitHeadAndBody(rawText)
        let lines = parts.head.components(separatedBy: "\n")
        guard let firstLine = lines.first, !firstLine.isEmpty else { return nil }

        // 解析请求行: "METHOD /path HTTP/1.1" 或 "METHOD http://host/path HTTP/1.1"
        let (method, path, version) = parseRequestLine(firstLine)
        guard !method.isEmpty else { return nil }

        // 解析 Headers（直到空行）
        var headers: [(String, String)] = []
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty {
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.append((name, value))
            }
        }

        // 提取 Host
        let host = extractHost(from: path) ?? headers.first(where: { $0.0.lowercased() == "host" })?.1 ?? ""

        // 清理 path（如果包含完整 URL，只保留 path 部分）
        let cleanPath = cleanPath(from: path)

        return HTTPRequest(
            method: method,
            host: host,
            path: cleanPath,
            httpVersion: version,
            headers: headers,
            body: parts.body
        )
    }

    static func bodyByteCount(_ rawText: String) -> Int {
        splitHeadAndBody(rawText).body.data(using: .utf8)?.count ?? 0
    }

    private static func splitHeadAndBody(_ rawText: String) -> (head: String, body: String) {
        if let range = rawText.range(of: "\r\n\r\n") {
            return (String(rawText[..<range.lowerBound]), String(rawText[range.upperBound...]))
        }
        if let range = rawText.range(of: "\n\n") {
            return (String(rawText[..<range.lowerBound]), String(rawText[range.upperBound...]))
        }
        return (rawText, "")
    }

    /// 解析请求行
    private static func parseRequestLine(_ line: String) -> (method: String, path: String, version: String) {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        let parts = trimmed.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return ("", "", "HTTP/1.1") }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])
        let version = parts.count > 2 ? String(parts[2]) : "HTTP/1.1"
        return (method, path, version)
    }

    /// 从 URL 字符串提取 host
    private static func extractHost(from path: String) -> String? {
        // "http://host:port/path" 或 "https://host/path"
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            guard let url = URL(string: path) else { return nil }
            if let port = url.port, port != 80, port != 443 {
                return "\(url.host ?? ""):\(port)"
            }
            return url.host
        }
        return nil
    }

    /// 如果 path 是完整 URL，提取 path 部分
    private static func cleanPath(from path: String) -> String {
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            guard let url = URL(string: path) else { return path }
            var result = url.path.isEmpty ? "/" : url.path
            if let query = url.query {
                result += "?\(query)"
            }
            if let fragment = url.fragment {
                result += "#\(fragment)"
            }
            return result
        }
        return path
    }

    /// 从解析后的请求重新构建 raw text（用于注入头/更新 Content-Length 后）
    static func buildRaw(from request: HTTPRequest) -> String {
        var lines: [String] = []
        lines.append("\(request.method) \(request.path) \(request.httpVersion)")
        for (name, value) in request.headers {
            lines.append("\(name): \(value)")
        }
        lines.append("")
        if !request.body.isEmpty {
            lines.append(request.body)
        }
        return lines.joined(separator: "\r\n")
    }
}
