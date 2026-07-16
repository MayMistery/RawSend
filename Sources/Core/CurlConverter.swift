import Foundation

/// cURL 命令与 Raw HTTP 报文互转。
///
/// `curlToRaw` / `convert` 提供“无敌”级别的 curl 解析：支持从浏览器
/// DevTools（bash / cmd）、Postman、Insomnia 等复制出的各种 curl 写法。
struct CurlConverter {

    // MARK: - 结果类型

    /// curl → raw 的转换结果
    struct ConversionResult: Equatable {
        /// 生成的 raw HTTP 报文（以 "\n" 分隔，body 前有一个空行）
        let raw: String
        /// 从 URL 中探测到的协议（"http" / "https" / 其它），无法确定时为 nil
        let scheme: String?
    }

    // MARK: - cURL → Raw（对外主入口）

    /// 将 curl 命令解析并转换为 raw HTTP 报文 + 探测到的协议
    static func convert(_ curlCommand: String) -> ConversionResult? {
        guard let parsed = parse(curlCommand) else { return nil }
        return ConversionResult(raw: buildRaw(from: parsed), scheme: parsed.scheme)
    }

    /// 兼容旧接口：只返回 raw 文本
    static func curlToRaw(_ curlCommand: String) -> String? {
        convert(curlCommand)?.raw
    }

    // MARK: - 检测

    /// 检测文本是否为 curl 命令
    static func isCurlCommand(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉可能被一起复制的 shell 提示符（"$ " / "> "）
        if trimmed.hasPrefix("$") || trimmed.hasPrefix(">") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let lower = trimmed.lowercased()
        if lower == "curl" { return true }
        // 支持 "curl ..."、"curl\t..."、换行以及 "/usr/bin/curl ..."
        for prefix in ["curl ", "curl\t", "curl\n", "curl\r"] where lower.hasPrefix(prefix) {
            return true
        }
        if let firstToken = lower.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first {
            return firstToken == "curl" || firstToken.hasSuffix("/curl")
        }
        return false
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

    // MARK: - 内部解析模型

    private struct FormPart {
        var name: String
        var value: String
        var isFile: Bool = false
        var filename: String?
        var contentType: String?
    }

    private struct ParsedCurl {
        var method: String
        var host: String
        var pathAndQuery: String
        var scheme: String?
        var headers: [(String, String)]
        var body: String
        var hasHostHeader: Bool
    }

    /// 收集 curl 命令行中的所有信息（尚未组装成 raw）
    private struct Collector {
        var explicitMethod: String?
        var head = false
        var upload = false
        var get = false
        var compressed = false
        var urls: [String] = []
        var headers: [(String, String)] = []      // 来自 -H，保持顺序
        var dataParts: [String] = []              // -d / --data* / --data-urlencode，之间用 & 连接
        var jsonParts: [String] = []              // --json，直接拼接
        var forms: [FormPart] = []                // -F / --form
        var basicUser: String?                    // -u
        var bearer: String?                       // --oauth2-bearer
        var cookies: [String] = []                // -b（含 '='）
        var userAgent: String?                    // -A
        var referer: String?                      // -e
        var range: String?                        // -r
    }

    // MARK: - 解析主流程

    private static func parse(_ curlCommand: String) -> ParsedCurl? {
        let tokens = tokenize(curlCommand)
        guard let curlIndex = tokens.firstIndex(where: {
            let l = $0.lowercased()
            return l == "curl" || l == "curl.exe" || l.hasSuffix("/curl") || l.hasSuffix("/curl.exe")
        }) else { return nil }

        var collector = Collector()
        var i = curlIndex + 1

        // 读取当前 flag 的取值：优先使用 "--flag=value" 内联值，否则取下一个 token
        func advanceValue(_ inlineValue: String?) -> String {
            if let inlineValue { return inlineValue }
            if i + 1 < tokens.count {
                i += 1
                return tokens[i]
            }
            return ""
        }

        while i < tokens.count {
            let token = tokens[i]

            if token == "--" {
                // curl 并不使用 "--" 分隔符，容错跳过
                i += 1
                continue
            }

            if token.hasPrefix("--") {
                let raw = String(token.dropFirst(2))
                let name: String
                let inlineValue: String?
                if let eq = raw.firstIndex(of: "=") {
                    name = String(raw[..<eq]).lowercased()
                    inlineValue = String(raw[raw.index(after: eq)...])
                } else {
                    name = raw.lowercased()
                    inlineValue = nil
                }
                handleLong(name, inlineValue: inlineValue, advanceValue: advanceValue, into: &collector)
            } else if token.hasPrefix("-") && token.count >= 2 {
                handleShortCluster(token, advanceValue: { advanceValue(nil) }, into: &collector)
            } else {
                collector.urls.append(token)
            }

            i += 1
        }

        return assemble(collector)
    }

    // MARK: - 长选项

    private static let longValueIgnored: Set<String> = [
        "connect-timeout", "max-time", "output", "cacert", "capath", "cert", "key",
        "cert-type", "key-type", "pass", "proxy", "proxy-user", "preproxy",
        "proxy-header", "resolve", "connect-to", "cookie-jar", "retry", "retry-delay",
        "retry-max-time", "limit-rate", "max-redirs", "write-out", "interface",
        "dns-servers", "speed-limit", "speed-time", "keepalive-time", "tls-max",
        "ciphers", "local-port", "stderr", "trace", "trace-ascii", "dump-header",
        "egd-file", "random-file", "noproxy", "unix-socket", "abstract-unix-socket",
        "happy-eyeballs-timeout-ms", "expect100-timeout", "login-options",
        "sasl-authzid", "proto", "proto-default", "proto-redir", "alt-svc", "hsts",
        "aws-sigv4", "request-target", "tftp-blksize", "mail-from", "mail-rcpt",
        "mail-auth", "ftp-account", "ftp-alternative-to-user", "ftp-method",
        "ftp-port", "krb", "telnet-option", "socks4", "socks4a", "socks5",
        "socks5-hostname", "socks5-gssapi-service", "service-name", "engine",
        "tls13-ciphers", "proxy-tls13-ciphers", "proxy-ciphers", "proxy-cacert",
        "proxy-capath", "proxy-cert", "proxy-key", "proxy-cert-type",
        "proxy-key-type", "proxy-pass", "proxy-service-name", "doh-url",
        "etag-save", "etag-compare", "output-dir", "create-file-mode", "curves",
        "pinnedpubkey", "hostpubmd5", "random", "delegation", "max-filesize",
        "continue-at",
    ]

    private static func handleLong(
        _ name: String,
        inlineValue: String?,
        advanceValue: (String?) -> String,
        into c: inout Collector
    ) {
        switch name {
        case "request":
            c.explicitMethod = advanceValue(inlineValue).uppercased()
        case "header":
            addHeader(advanceValue(inlineValue), into: &c)
        case "data", "data-ascii":
            c.dataParts.append(stripNewlines(advanceValue(inlineValue)))
        case "data-raw", "data-binary":
            c.dataParts.append(advanceValue(inlineValue))
        case "data-urlencode":
            c.dataParts.append(encodeDataUrlencode(advanceValue(inlineValue)))
        case "json":
            c.jsonParts.append(advanceValue(inlineValue))
        case "form":
            c.forms.append(parseForm(advanceValue(inlineValue), literal: false))
        case "form-string":
            c.forms.append(parseForm(advanceValue(inlineValue), literal: true))
        case "user":
            c.basicUser = advanceValue(inlineValue)
        case "oauth2-bearer":
            c.bearer = advanceValue(inlineValue)
        case "cookie":
            addCookie(advanceValue(inlineValue), into: &c)
        case "user-agent":
            c.userAgent = advanceValue(inlineValue)
        case "referer":
            c.referer = stripAuto(advanceValue(inlineValue))
        case "range":
            c.range = advanceValue(inlineValue)
        case "url":
            c.urls.append(advanceValue(inlineValue))
        case "head":
            c.head = true
        case "get":
            c.get = true
        case "compressed":
            c.compressed = true
        case "upload-file":
            c.upload = true
            _ = advanceValue(inlineValue) // 文件名，无法读取
        default:
            if longValueIgnored.contains(name) {
                _ = advanceValue(inlineValue)
            }
            // 其它未知长选项按布尔处理，不消耗后续 token
        }
    }

    // MARK: - 短选项（支持组合，如 -sSL，以及贴值，如 -XPOST）

    private static let shortValueIgnored: Set<Character> = [
        "m", "o", "x", "U", "c", "E", "y", "Y", "w", "D", "K", "P", "Q", "z", "t",
    ]

    private static func handleShortCluster(
        _ token: String,
        advanceValue: () -> String,
        into c: inout Collector
    ) {
        let chars = Array(token.dropFirst()) // 去掉前导 '-'
        var j = 0
        while j < chars.count {
            let ch = chars[j]
            let rest = j + 1 < chars.count ? String(chars[(j + 1)...]) : ""

            func value() -> String {
                if !rest.isEmpty { return rest }
                return advanceValue()
            }

            switch ch {
            case "X":
                c.explicitMethod = value().uppercased(); return
            case "H":
                addHeader(value(), into: &c); return
            case "d":
                c.dataParts.append(stripNewlines(value())); return
            case "F":
                c.forms.append(parseForm(value(), literal: false)); return
            case "u":
                c.basicUser = value(); return
            case "b":
                addCookie(value(), into: &c); return
            case "A":
                c.userAgent = value(); return
            case "e":
                c.referer = stripAuto(value()); return
            case "r":
                c.range = value(); return
            case "T":
                c.upload = true; _ = value(); return
            case "G":
                c.get = true; j += 1
            case "I":
                c.head = true; j += 1
            default:
                if shortValueIgnored.contains(ch) {
                    _ = value(); return
                }
                j += 1 // 其它布尔短选项（-k -L -s -S -v -f -i ...）忽略
            }
        }
    }

    // MARK: - 组装 raw

    private static func assemble(_ c: Collector) -> ParsedCurl? {
        // 1. 选出 URL：优先带 "://" 的，其次像 host 的，最后第一个
        let url = c.urls.first(where: { $0.contains("://") })
            ?? c.urls.first(where: { $0.contains(".") || $0.contains("{{") || $0.lowercased().hasPrefix("localhost") })
            ?? c.urls.first
        guard let urlString = url, !urlString.isEmpty else { return nil }

        let parsedURL = parseURL(urlString)
        var pathAndQuery = parsedURL.pathAndQuery

        // 2. 头部（来自 -H），并提供便捷判断
        var headers = c.headers
        func hasHeader(_ name: String) -> Bool {
            headers.contains { $0.0.caseInsensitiveCompare(name) == .orderedSame }
        }
        func removeHeader(_ name: String) {
            headers.removeAll { $0.0.caseInsensitiveCompare(name) == .orderedSame }
        }

        // 3. body / content-type
        var body = ""
        let hasFormData = !c.forms.isEmpty
        let hasJSON = !c.jsonParts.isEmpty
        let hasData = !c.dataParts.isEmpty

        if hasFormData {
            let boundary = "----RawSendFormBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            body = buildMultipart(c.forms, boundary: boundary)
            if !hasHeader("Content-Type") {
                headers.append(("Content-Type", "multipart/form-data; boundary=\(boundary)"))
            }
        } else if hasJSON {
            body = c.jsonParts.joined()
            if !hasHeader("Content-Type") { headers.append(("Content-Type", "application/json")) }
            if !hasHeader("Accept") { headers.append(("Accept", "application/json")) }
        } else if hasData {
            let joined = c.dataParts.joined(separator: "&")
            if c.get {
                // -G：数据拼到 query，不做 body
                pathAndQuery += pathAndQuery.contains("?") ? "&" + joined : "?" + joined
            } else {
                body = joined
                if !hasHeader("Content-Type") {
                    headers.append(("Content-Type", "application/x-www-form-urlencoded"))
                }
            }
        }

        // 4. 方法
        let hasBody = hasFormData || hasJSON || (hasData && !c.get)
        let method: String
        if let m = c.explicitMethod, !m.isEmpty {
            method = m
        } else if c.head {
            method = "HEAD"
        } else if c.upload {
            method = "PUT"
        } else if hasBody {
            method = "POST"
        } else {
            method = "GET"
        }

        // 5. 认证
        if !hasHeader("Authorization") {
            if let user = c.basicUser {
                headers.append(("Authorization", "Basic \(base64(user))"))
            } else if let bearer = c.bearer {
                headers.append(("Authorization", "Bearer \(bearer)"))
            } else if let userinfo = parsedURL.userinfo, !userinfo.isEmpty {
                headers.append(("Authorization", "Basic \(base64(userinfo))"))
            }
        }

        // 6. Cookie
        if !c.cookies.isEmpty {
            let joined = c.cookies.joined(separator: "; ")
            if let idx = headers.firstIndex(where: { $0.0.caseInsensitiveCompare("Cookie") == .orderedSame }) {
                headers[idx].1 = headers[idx].1.isEmpty ? joined : headers[idx].1 + "; " + joined
            } else {
                headers.append(("Cookie", joined))
            }
        }

        // 7. User-Agent（-A 覆盖）
        if let ua = c.userAgent {
            removeHeader("User-Agent")
            headers.append(("User-Agent", ua))
        }

        // 8. Referer
        if let referer = c.referer, !hasHeader("Referer") {
            headers.append(("Referer", referer))
        }

        // 9. Range
        if let range = c.range, !hasHeader("Range") {
            let value = range.contains("=") ? range : "bytes=\(range)"
            headers.append(("Range", value))
        }

        // 10. --compressed
        if c.compressed, !hasHeader("Accept-Encoding") {
            headers.append(("Accept-Encoding", "gzip, deflate, br"))
        }

        // Host：优先使用 -H 提供的 Host
        let hasHostHeader = hasHeader("Host")
        let host: String
        if let hostHeader = headers.first(where: { $0.0.caseInsensitiveCompare("Host") == .orderedSame }) {
            host = hostHeader.1
        } else {
            host = parsedURL.hostPort
        }

        return ParsedCurl(
            method: method,
            host: host,
            pathAndQuery: pathAndQuery.isEmpty ? "/" : pathAndQuery,
            scheme: parsedURL.scheme,
            headers: headers,
            body: body,
            hasHostHeader: hasHostHeader
        )
    }

    private static func buildRaw(from parsed: ParsedCurl) -> String {
        var lines: [String] = ["\(parsed.method) \(parsed.pathAndQuery) HTTP/1.1"]
        if !parsed.hasHostHeader {
            lines.append("Host: \(parsed.host)")
        }
        for (name, value) in parsed.headers {
            lines.append("\(name): \(value)")
        }
        lines.append("")
        if !parsed.body.isEmpty {
            lines.append(parsed.body)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 头 / Cookie / Form 辅助

    private static func addHeader(_ raw: String, into c: inout Collector) {
        if let colon = raw.firstIndex(of: ":") {
            let name = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            // "Name:"（冒号后为空）在 curl 中表示禁用该头，跳过
            if value.isEmpty { return }
            c.headers.append((name, value))
        } else if raw.hasSuffix(";") {
            // "Name;" 表示发送空值头
            let name = String(raw.dropLast()).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { c.headers.append((name, "")) }
        }
    }

    private static func addCookie(_ value: String, into c: inout Collector) {
        // 含 '=' 视为 cookie 数据，否则视为 cookie 文件（无法读取，忽略）
        if value.contains("=") { c.cookies.append(value) }
    }

    private static func parseForm(_ raw: String, literal: Bool) -> FormPart {
        guard let eq = raw.firstIndex(of: "=") else {
            return FormPart(name: raw, value: "")
        }
        let name = String(raw[..<eq])
        var rest = String(raw[raw.index(after: eq)...])
        var part = FormPart(name: name, value: "")

        if !literal, rest.hasPrefix("@") || rest.hasPrefix("<") {
            let isUpload = rest.hasPrefix("@")
            rest.removeFirst()
            let segs = rest.components(separatedBy: ";")
            let path = segs.first ?? ""
            part.isFile = isUpload
            if isUpload {
                part.filename = (path as NSString).lastPathComponent
            }
            for seg in segs.dropFirst() {
                let s = seg.trimmingCharacters(in: .whitespaces)
                let lower = s.lowercased()
                if lower.hasPrefix("type=") {
                    part.contentType = String(s.dropFirst(5))
                } else if lower.hasPrefix("filename=") {
                    part.filename = String(s.dropFirst(9))
                }
            }
            part.value = "" // 无法读取文件内容
        } else {
            part.value = rest
        }
        return part
    }

    private static func buildMultipart(_ forms: [FormPart], boundary: String) -> String {
        var s = ""
        for f in forms {
            s += "--\(boundary)\r\n"
            if f.isFile {
                let filename = f.filename ?? "file"
                s += "Content-Disposition: form-data; name=\"\(f.name)\"; filename=\"\(filename)\"\r\n"
                s += "Content-Type: \(f.contentType ?? "application/octet-stream")\r\n\r\n"
                s += f.value
                s += "\r\n"
            } else {
                s += "Content-Disposition: form-data; name=\"\(f.name)\"\r\n"
                if let ct = f.contentType { s += "Content-Type: \(ct)\r\n" }
                s += "\r\n\(f.value)\r\n"
            }
        }
        s += "--\(boundary)--\r\n"
        return s
    }

    // MARK: - 值处理辅助

    private static func stripNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }

    private static func stripAuto(_ s: String) -> String {
        s.hasSuffix(";auto") ? String(s.dropLast(5)) : s
    }

    private static func base64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
    }

    private static func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// 处理 --data-urlencode 的多种形式：content / =content / name=content / @file / name@file
    private static func encodeDataUrlencode(_ v: String) -> String {
        if let eq = v.firstIndex(of: "=") {
            let name = String(v[..<eq])
            let content = String(v[v.index(after: eq)...])
            if name.isEmpty { return urlEncode(content) }
            return name + "=" + urlEncode(content)
        }
        if let at = v.firstIndex(of: "@") {
            // name@file 或 @file：无法读取文件
            let name = String(v[..<at])
            return name.isEmpty ? "" : name + "="
        }
        return urlEncode(v)
    }

    // MARK: - URL 解析（手写，兼容 {{变量}} 等 Foundation 无法解析的 URL）

    private struct URLParts {
        var scheme: String?
        var userinfo: String?
        var hostPort: String
        var pathAndQuery: String
    }

    private static func parseURL(_ raw: String) -> URLParts {
        var s = raw
        var scheme: String?

        if let sep = s.range(of: "://") {
            let candidate = String(s[..<sep.lowerBound])
            if candidate.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil {
                scheme = candidate.lowercased()
                s = String(s[sep.upperBound...])
            }
        }

        // authority 到第一个 / ? # 为止
        var authority = s
        var rest = ""
        if let idx = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            authority = String(s[..<idx])
            rest = String(s[idx...])
        }

        // userinfo@host
        var userinfo: String?
        if let at = authority.lastIndex(of: "@") {
            userinfo = String(authority[..<at])
            authority = String(authority[authority.index(after: at)...])
        }

        // path + query（丢弃 fragment）
        var pathAndQuery = rest
        if let hash = pathAndQuery.firstIndex(of: "#") {
            pathAndQuery = String(pathAndQuery[..<hash])
        }
        if pathAndQuery.isEmpty {
            pathAndQuery = "/"
        } else if !pathAndQuery.hasPrefix("/") {
            pathAndQuery = "/" + pathAndQuery
        }

        return URLParts(scheme: scheme, userinfo: userinfo, hostPort: authority, pathAndQuery: pathAndQuery)
    }

    // MARK: - Shell 分词

    /// 稳健的 shell 分词：支持单引号 / 双引号 / ANSI-C 引用 $'...'、
    /// 反斜杠与脱字符(^)续行、以及相邻片段拼接（如 -H'A: b' → 一个 token）。
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        let chars = Array(input)
        let n = chars.count
        var i = 0

        func flush() {
            if hasCurrent {
                tokens.append(current)
                current = ""
                hasCurrent = false
            }
        }

        while i < n {
            let c = chars[i]

            // 空白：分隔 token
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                flush()
                i += 1
                continue
            }

            // 反斜杠：续行或转义
            if c == "\\" {
                if i + 1 < n {
                    let next = chars[i + 1]
                    if next == "\n" { i += 2; continue }
                    if next == "\r" {
                        i += (i + 2 < n && chars[i + 2] == "\n") ? 3 : 2
                        continue
                    }
                    current.append(next); hasCurrent = true; i += 2; continue
                }
                i += 1
                continue
            }

            // 脱字符续行（Windows cmd）：仅当其后紧跟换行时
            if c == "^" {
                if i + 1 < n && (chars[i + 1] == "\n" || chars[i + 1] == "\r") {
                    i += 1
                    while i < n && (chars[i] == "\n" || chars[i] == "\r") { i += 1 }
                    continue
                }
                current.append(c); hasCurrent = true; i += 1; continue
            }

            // 单引号
            if c == "'" {
                hasCurrent = true
                i += 1
                while i < n && chars[i] != "'" { current.append(chars[i]); i += 1 }
                if i < n { i += 1 }
                continue
            }

            // ANSI-C 引用 $'...'
            if c == "$" && i + 1 < n && chars[i + 1] == "'" {
                hasCurrent = true
                i += 2
                while i < n && chars[i] != "'" {
                    if chars[i] == "\\" && i + 1 < n {
                        let next = chars[i + 1]
                        switch next {
                        case "n": current.append("\n"); i += 2
                        case "t": current.append("\t"); i += 2
                        case "r": current.append("\r"); i += 2
                        case "\\": current.append("\\"); i += 2
                        case "'": current.append("'"); i += 2
                        case "\"": current.append("\""); i += 2
                        case "a": current.append("\u{07}"); i += 2
                        case "b": current.append("\u{08}"); i += 2
                        case "f": current.append("\u{0C}"); i += 2
                        case "v": current.append("\u{0B}"); i += 2
                        case "e": current.append("\u{1B}"); i += 2
                        case "x":
                            var hex = ""
                            var k = i + 2
                            while k < n && hex.count < 2 && chars[k].isHexDigit { hex.append(chars[k]); k += 1 }
                            if let v = UInt32(hex, radix: 16), let sc = Unicode.Scalar(v) {
                                current.append(Character(sc))
                            }
                            i = k
                        case "u":
                            var hex = ""
                            var k = i + 2
                            while k < n && hex.count < 4 && chars[k].isHexDigit { hex.append(chars[k]); k += 1 }
                            if let v = UInt32(hex, radix: 16), let sc = Unicode.Scalar(v) {
                                current.append(Character(sc))
                            }
                            i = k
                        default:
                            current.append(next); i += 2
                        }
                    } else {
                        current.append(chars[i]); i += 1
                    }
                }
                if i < n { i += 1 }
                continue
            }

            // 双引号
            if c == "\"" {
                hasCurrent = true
                i += 1
                while i < n && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < n {
                        let next = chars[i + 1]
                        if next == "\"" || next == "\\" || next == "$" || next == "`" {
                            current.append(next); i += 2; continue
                        }
                        if next == "\n" { i += 2; continue }
                        current.append(chars[i]); i += 1; continue
                    }
                    current.append(chars[i]); i += 1
                }
                if i < n { i += 1 }
                continue
            }

            // 普通字符
            current.append(c)
            hasCurrent = true
            i += 1
        }

        flush()
        return tokens
    }
}
