import Foundation

/// 请求发送引擎：支持并行双发 HTTP/HTTPS
actor RequestSender {

    /// 发送结果
    struct SendResult {
        let httpResponse: HTTPResponse?
        let httpsResponse: HTTPResponse?
    }

    /// 并行发送 HTTP 和 HTTPS 请求
    func send(
        request: HTTPRequest,
        rawText: String,
        sendHTTP: Bool,
        sendHTTPS: Bool,
        environment: Environment?,
        defaultHeaders: [DefaultHeader],
        preferences: AppPreferences,
        manuallyStruckHeaderIDs: Set<HeaderLine.ID> = [],
        manuallyStruckQueryParameterIDs: Set<QueryParameter.ID> = [],
        redactionKeywords: [String] = [],
        redactMatchingHeaders: Bool = true
    ) async -> SendResult {
        // 1. 变量替换
        let resolvedText = VariableEngine.resolve(rawText, environment: environment)

        // 2. 重新解析（变量替换后可能改变了 host 等）
        guard var resolved = RequestParser.parse(resolvedText) else {
            let err = HTTPResponse.error(Localizer.text(.invalidRawRequest, language: preferences.appLanguage))
            return SendResult(httpResponse: sendHTTP ? err : nil, httpsResponse: sendHTTPS ? err : nil)
        }

        // 3. 注入默认头（不覆盖已有同名头）
        let existingHeaderNames = Set(resolved.headers.map { $0.0.lowercased() })
        for header in defaultHeaders where header.isEnabled {
            if !existingHeaderNames.contains(header.name.lowercased()) {
                let resolvedValue = VariableEngine.resolve(header.value, environment: environment)
                resolved.headers.append((header.name, resolvedValue))
            }
        }

        // 4. 计算 Content-Length
        if !resolved.body.isEmpty {
            let bodyLength = resolved.body.data(using: .utf8)?.count ?? 0
            // 移除已有的 Content-Length
            resolved.headers.removeAll(where: { $0.0.lowercased() == "content-length" })
            resolved.headers.append(("Content-Length", String(bodyLength)))
        } else if ["POST", "PUT", "PATCH"].contains(resolved.method.uppercased()) {
            resolved.headers.removeAll(where: { $0.0.lowercased() == "content-length" })
            resolved.headers.append(("Content-Length", "0"))
        }

        // 5. 过滤被划掉的 Header
        let headerFilteredRequest = HeaderInspector.filteredRequest(
            resolved,
            manuallyStruckIDs: manuallyStruckHeaderIDs,
            keywords: redactionKeywords,
            redactMatchingKeywords: redactMatchingHeaders
        )
        let finalRequest = QueryParameterInspector.filteredRequest(
            headerFilteredRequest,
            manuallyStruckIDs: manuallyStruckQueryParameterIDs,
            keywords: redactionKeywords,
            redactMatchingKeywords: redactMatchingHeaders
        )

        // 6. 并行发送
        async let httpResult: HTTPResponse? = sendHTTP ? sendRequest(finalRequest, scheme: "http", preferences: preferences) : nil
        async let httpsResult: HTTPResponse? = sendHTTPS ? sendRequest(finalRequest, scheme: "https", preferences: preferences) : nil

        return SendResult(httpResponse: await httpResult, httpsResponse: await httpsResult)
    }

    /// 发送单个请求
    private func sendRequest(_ request: HTTPRequest, scheme: String, preferences: AppPreferences) async -> HTTPResponse {
        let urlString = "\(scheme)://\(request.host)\(request.path)"
        guard let url = URL(string: urlString) else {
            let message = Localizer.format(.invalidURL, language: preferences.appLanguage, urlString)
            let debugInfo = makeDebugInfo(message: message, scheme: scheme, request: request, urlString: urlString)
            ErrorLogStore.append(debugInfo)
            return .error(message, debugInfo: debugInfo)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = preferences.timeoutSeconds

        for (name, value) in request.headers {
            if name.lowercased() == "host" { continue } // URLSession 自动处理
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        if !request.body.isEmpty {
            urlRequest.httpBody = request.body.data(using: .utf8)
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = preferences.timeoutSeconds
        config.httpShouldSetCookies = false

        let delegate = SessionDelegate(
            ignoreTLS: preferences.ignoreTLSErrors,
            followRedirects: preferences.followRedirects
        )
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let startTime = Date()
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let elapsed = Date().timeIntervalSince(startTime)
            return HTTPResponse(urlResponse: response as? HTTPURLResponse, data: data, elapsed: elapsed)
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            let debugInfo = makeDebugInfo(
                message: error.localizedDescription,
                scheme: scheme,
                request: request,
                urlString: urlString
            )
            ErrorLogStore.append(debugInfo)
            return HTTPResponse.error(error.localizedDescription, elapsed: elapsed, debugInfo: debugInfo)
        }
    }

    private func makeDebugInfo(
        message: String,
        scheme: String,
        request: HTTPRequest,
        urlString: String
    ) -> ResponseDebugInfo {
        ResponseDebugInfo(
            errorMessage: message,
            scheme: scheme,
            request: request,
            url: urlString,
            localLogPath: ErrorLogStore.logFileURL.path
        )
    }
}

// MARK: - URLSession Delegate

private class SessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let ignoreTLS: Bool
    let followRedirects: Bool

    init(ignoreTLS: Bool, followRedirects: Bool) {
        self.ignoreTLS = ignoreTLS
        self.followRedirects = followRedirects
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if ignoreTLS, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if followRedirects {
            completionHandler(request)
        } else {
            completionHandler(nil) // 阻止重定向
        }
    }
}
