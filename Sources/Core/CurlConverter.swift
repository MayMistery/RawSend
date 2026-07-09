import Foundation

/// cURL 命令与 Raw HTTP 报文互转
struct CurlConverter {

    // MARK: - cURL → Raw

    /// 将 curl 命令转换为 raw HTTP 报文
    static func curlToRaw(_ curlCommand: String) -> String? {
        let trimmed = curlCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("curl") else { return nil }

        // 简单解析 curl 参数
        let tokens = tokenize(trimmed)
        guard tokens.count > 1 else { return nil }

        var method = "GET"
        var url = ""
        var headers: [(String, String)] = []
        var body: String? = nil

        var i = 1 // 跳过 "curl"
        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case "-X", "--request":
                i += 1
                if i < tokens.count { method = tokens[i].uppercased() }
            case "-H", "--header":
                i += 1
                if i < tokens.count {
                    let header = tokens[i]
                    if let colonIdx = header.firstIndex(of: ":") {
                        let name = String(header[header.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let value = String(header[header.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        headers.append((name, value))
                    }
                }
            case "-d", "--data", "--data-raw", "--data-binary":
                i += 1
                if i < tokens.count {
                    body = tokens[i]
                    if method == "GET" { method = "POST" }
                }
            case "-k", "--insecure":
                break // 忽略（我们默认就忽略证书）
            case "-L", "--location":
                break // 忽略重定向标志
            default:
                // 没有前缀的参数认为是 URL
                if !token.hasPrefix("-") && url.isEmpty {
                    url = token
                }
            }
            i += 1
        }

        guard !url.isEmpty else { return nil }

        // 构建 raw 报文
        let urlObj = URL(string: url)
        let path = urlObj?.path.isEmpty == true ? "/" : (urlObj?.path ?? "/")
        let query = urlObj?.query.map { "?\($0)" } ?? ""
        let host = urlObj?.host ?? ""
        let port = urlObj?.port

        var lines: [String] = []
        lines.append("\(method) \(path)\(query) HTTP/1.1")

        // 如果 headers 中没有 Host，自动加
        if !headers.contains(where: { $0.0.lowercased() == "host" }) {
            var hostValue = host
            if let p = port, p != 80, p != 443 {
                hostValue += ":\(p)"
            }
            lines.append("Host: \(hostValue)")
        }

        for (name, value) in headers {
            lines.append("\(name): \(value)")
        }

        lines.append("")
        if let body = body {
            lines.append(body)
        }

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Raw → cURL

    /// 将 raw HTTP 报文转换为 curl 命令
    static func rawToCurl(
        _ rawText: String,
        scheme: String = "https",
        manuallyStruckIDs: Set<HeaderLine.ID> = [],
        manuallyStruckQueryParameterIDs: Set<QueryParameter.ID> = [],
        redactionKeywords: [String] = [],
        redactMatchingKeywords: Bool = true
    ) -> String? {
        guard let parsed = RequestParser.parse(rawText) else { return nil }
        let headerFiltered = HeaderInspector.filteredRequest(
            parsed,
            manuallyStruckIDs: manuallyStruckIDs,
            keywords: redactionKeywords,
            redactMatchingKeywords: redactMatchingKeywords
        )
        let request = QueryParameterInspector.filteredRequest(
            headerFiltered,
            manuallyStruckIDs: manuallyStruckQueryParameterIDs,
            keywords: redactionKeywords,
            redactMatchingKeywords: redactMatchingKeywords
        )

        var parts: [String] = ["curl"]
        parts.append("-X \(request.method)")

        let url = "\(scheme)://\(request.host)\(request.path)"
        parts.append("'\(url)'")

        for (name, value) in request.headers {
            if name.lowercased() == "host" { continue } // Host 已在 URL 中
            if name.lowercased() == "content-length" { continue } // curl 自动计算
            let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(name): \(escaped)'")
        }

        if !request.body.isEmpty {
            let escaped = request.body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escaped)'")
        }

        parts.append("-k") // 忽略证书

        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - 检测

    /// 检测文本是否为 curl 命令
    static func isCurlCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("curl ")
    }

    // MARK: - Private

    /// 简单 shell 命令分词（处理引号）
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escape = false

        for char in input {
            if escape {
                current.append(char)
                escape = false
                continue
            }
            if char == "\\" && !inSingleQuote {
                escape = true
                continue
            }
            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(char)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
