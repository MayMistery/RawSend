import Foundation

/// 请求发送引擎：支持并行双发 HTTP/HTTPS
actor RequestSender {

    struct SentExchange {
        let id: UUID
        let scheme: String
        let request: HTTPRequest
        let response: HTTPResponse
        let originPluginID: String?
        let variantID: String?
        let metadata: [String: String]

        init(
            id: UUID = UUID(),
            scheme: String,
            request: HTTPRequest,
            response: HTTPResponse,
            originPluginID: String? = nil,
            variantID: String? = nil,
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.scheme = scheme
            self.request = request
            self.response = response
            self.originPluginID = originPluginID
            self.variantID = variantID
            self.metadata = metadata
        }
    }

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
        guard let finalRequest = prepare(
            rawText: rawText,
            environment: environment,
            defaultHeaders: defaultHeaders,
            manuallyStruckHeaderIDs: manuallyStruckHeaderIDs,
            manuallyStruckQueryParameterIDs: manuallyStruckQueryParameterIDs,
            redactionKeywords: redactionKeywords,
            redactMatchingHeaders: redactMatchingHeaders
        ) else {
            let err = HTTPResponse.error(Localizer.text(.invalidRawRequest, language: preferences.appLanguage))
            return SendResult(httpResponse: sendHTTP ? err : nil, httpsResponse: sendHTTPS ? err : nil)
        }

        let schemes = [
            sendHTTP ? "http" : nil,
            sendHTTPS ? "https" : nil,
        ].compactMap { $0 }
        let exchanges = await sendPrepared(
            finalRequest,
            schemes: schemes,
            preferences: preferences
        )
        return SendResult(
            httpResponse: exchanges.first { $0.scheme == "http" }?.response,
            httpsResponse: exchanges.first { $0.scheme == "https" }?.response
        )
    }

    func prepare(
        rawText: String,
        environment: Environment?,
        defaultHeaders: [DefaultHeader],
        manuallyStruckHeaderIDs: Set<HeaderLine.ID> = [],
        manuallyStruckQueryParameterIDs: Set<QueryParameter.ID> = [],
        redactionKeywords: [String] = [],
        redactMatchingHeaders: Bool = true
    ) -> HTTPRequest? {
        // 1. 变量替换
        let resolvedText = VariableEngine.resolve(rawText, environment: environment)

        // 2. 重新解析（变量替换后可能改变了 host 等）
        guard var resolved = RequestParser.parse(resolvedText) else {
            return nil
        }

        // 3. 注入默认头（不覆盖已有同名头）
        let existingHeaderNames = Set(resolved.headers.map { $0.0.lowercased() })
        for header in defaultHeaders where header.isEnabled {
            if !existingHeaderNames.contains(header.name.lowercased()) {
                let resolvedValue = VariableEngine.resolve(header.value, environment: environment)
                resolved.headers.append((header.name, resolvedValue))
            }
        }

        // 4. 过滤被划掉的 Header / Query 参数
        let headerFilteredRequest = HeaderInspector.filteredRequest(
            resolved,
            manuallyStruckIDs: manuallyStruckHeaderIDs,
            keywords: redactionKeywords,
            redactMatchingKeywords: redactMatchingHeaders
        )
        let filtered = QueryParameterInspector.filteredRequest(
            headerFilteredRequest,
            manuallyStruckIDs: manuallyStruckQueryParameterIDs,
            keywords: redactionKeywords,
            redactMatchingKeywords: redactMatchingHeaders
        )
        // 插件可能继续改写 body；发送前和每次变异后都由同一处重算。
        return RequestFieldExtractor.recomputingContentLength(filtered)
    }

    func sendPrepared(
        _ request: HTTPRequest,
        schemes: [String],
        preferences: AppPreferences,
        originPluginID: String? = nil,
        variantID: String? = nil,
        metadata: [String: String] = [:]
    ) async -> [SentExchange] {
        await withTaskGroup(of: SentExchange?.self) { group in
            for scheme in schemes where scheme == "http" || scheme == "https" {
                group.addTask {
                    let response = await self.sendRequest(request, scheme: scheme, preferences: preferences)
                    return SentExchange(
                        scheme: scheme,
                        request: request,
                        response: response,
                        originPluginID: originPluginID,
                        variantID: variantID,
                        metadata: metadata
                    )
                }
            }
            var exchanges: [SentExchange] = []
            for await exchange in group {
                if let exchange { exchanges.append(exchange) }
            }
            return exchanges.sorted { $0.scheme < $1.scheme }
        }
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
