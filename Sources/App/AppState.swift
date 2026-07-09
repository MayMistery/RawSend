import SwiftUI

/// 全局应用状态
@MainActor
class AppState: ObservableObject {
    // 编辑区
    @Published var rawText: String = """
    GET / HTTP/1.1
    Host: example.com
    Accept: */*

    """

    // 发送选项
    @Published var sendHTTP: Bool = true
    @Published var sendHTTPS: Bool = true
    @Published var isSending: Bool = false

    // 响应
    @Published var httpResponse: HTTPResponse?
    @Published var httpsResponse: HTTPResponse?
    @Published var selectedResponseTab: ResponseTab = .https

    // 环境
    @Published var environments: [Environment] = []
    @Published var selectedEnvironmentId: UUID?
    @Published var showEnvironmentPicker: Bool = false

    // 默认头
    @Published var defaultHeaders: [DefaultHeader] = []
    @Published var manuallyStruckHeaderIDs: Set<HeaderLine.ID> = []
    @Published var manuallyStruckQueryParameterIDs: Set<QueryParameter.ID> = []

    // 搜索
    @Published var requestSearchText: String = ""
    @Published var selectedRequestSearchIndex: Int?
    @Published private(set) var requestSearchMatches: [SearchMatch] = []
    @Published var responseSearchText: String = ""
    @Published var selectedResponseSearchIndex: Int?
    @Published private(set) var responseSearchMatches: [SearchMatch] = []
    @Published var requestSearchFocusToken: Int = 0
    @Published var responseSearchFocusToken: Int = 0
    @Published var activeSearchScope: SearchScope = .request
    private var responseSearchSource: String = ""
    private var requestSearchTask: Task<Void, Never>?
    private var responseSearchTask: Task<Void, Never>?
    private let searchDebounceNanoseconds: UInt64 = 120_000_000

    // Codex
    @Published var showCodexChat: Bool = false
    @Published var codexDraft: String = ""
    @Published var codexMessages: [CodexChatMessage] = []
    @Published var isCodexRunning: Bool = false
    @Published var codexErrorMessage: String?
    @Published var riskHighlights: [RiskHighlight] = []

    // 偏好
    @Published var preferences: AppPreferences = AppPreferences()

    // 设置
    @Published var showSettings: Bool = false

    // 历史
    @Published var history: [HistoryItem] = []
    @Published var showHistory: Bool = false

    // 解析状态
    @Published var parsedHost: String = ""
    @Published var bodySize: Int = 0
    @Published var variableCount: Int = 0
    @Published var undefinedVars: [String] = []

    enum ResponseTab: String, CaseIterable {
        case http = "HTTP"
        case https = "HTTPS"
        case diff = "Diff"
    }

    enum SearchScope {
        case request
        case response
    }

    var selectedEnvironment: Environment? {
        environments.first(where: { $0.id == selectedEnvironmentId })
    }

    var appLanguage: AppLanguage {
        preferences.appLanguage
    }

    func t(_ key: L10nKey) -> String {
        Localizer.text(key, language: appLanguage)
    }

    func tf(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        Localizer.format(key, language: appLanguage, arguments: arguments)
    }

    var requestHeaderLines: [HeaderLine] {
        guard let parsed = RequestParser.parse(rawText) else { return [] }
        let keywords = preferences.redactMatchingHeaders ? preferences.redactionKeywords : []
        return HeaderInspector.makeHeaderLines(
            from: parsed.headers,
            manuallyStruckIDs: manuallyStruckHeaderIDs,
            keywords: keywords
        )
    }

    var importantRequestHeaders: [HeaderLine] {
        HeaderInspector.importantHeaders(from: requestHeaderLines, names: preferences.importantHeaderNames)
    }

    var requestQueryParameters: [QueryParameter] {
        guard let parsed = RequestParser.parse(rawText) else { return [] }
        let keywords = preferences.redactMatchingHeaders ? preferences.redactionKeywords : []
        return QueryParameterInspector.makeParameters(
            from: parsed.path,
            manuallyStruckIDs: manuallyStruckQueryParameterIDs,
            keywords: keywords
        )
    }

    private let sender = RequestSender()
    private let codexService = CodexService()

    init() {
        loadData()
    }

    func loadData() {
        environments = PersistenceManager.shared.loadEnvironments()
        defaultHeaders = PersistenceManager.shared.loadDefaultHeaders()
        preferences = PersistenceManager.shared.loadPreferences()
        if selectedEnvironmentId == nil {
            selectedEnvironmentId = environments.first?.id
        }
        updateParseStatus()
        updateRequestSearchMatches(resetSelection: true)
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                PersistenceManager.shared.loadHistory()
            }.value
            self.history = loaded
        }
    }

    func saveAll() {
        PersistenceManager.shared.saveEnvironments(environments)
        PersistenceManager.shared.saveDefaultHeaders(defaultHeaders)
        PersistenceManager.shared.savePreferences(preferences)
        PersistenceManager.shared.saveHistory(history)
    }

    // MARK: - 解析状态更新

    func updateParseStatus() {
        if let parsed = RequestParser.parse(rawText) {
            parsedHost = parsed.host
            bodySize = RequestParser.bodyByteCount(rawText)
        } else {
            parsedHost = ""
            bodySize = 0
        }
        let vars = VariableEngine.extractVariables(rawText)
        variableCount = vars.count
        undefinedVars = VariableEngine.undefinedVariables(rawText, environment: selectedEnvironment)
    }

    // MARK: - 发送请求

    func sendRequest(followRedirectsOverride: Bool? = nil) {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !parsedHost.isEmpty else { return }
        guard sendHTTP || sendHTTPS else { return }

        isSending = true
        httpResponse = nil
        httpsResponse = nil
        responseSearchMatches = []
        selectedResponseSearchIndex = nil

        // 检查是否为 cURL 命令
        var textToSend = rawText
        if CurlConverter.isCurlCommand(rawText) {
            if let converted = CurlConverter.curlToRaw(rawText) {
                textToSend = converted
                rawText = converted
            }
        }

        guard let request = RequestParser.parse(textToSend) else {
            isSending = false
            return
        }

        // 保存到历史
        let historyItem = HistoryItem(rawText: rawText, request: request, environmentName: selectedEnvironment?.name)
        let historyID = historyItem.id
        history.insert(historyItem, at: 0)
        if history.count > preferences.maxHistoryCount {
            history = Array(history.prefix(preferences.maxHistoryCount))
        }
        PersistenceManager.shared.saveHistory(history)

        var sendPreferences = preferences
        if let followRedirectsOverride {
            sendPreferences.followRedirects = followRedirectsOverride
        }

        Task {
            let result = await sender.send(
                request: request,
                rawText: textToSend,
                sendHTTP: sendHTTP,
                sendHTTPS: sendHTTPS,
                environment: selectedEnvironment,
                defaultHeaders: defaultHeaders,
                preferences: sendPreferences,
                manuallyStruckHeaderIDs: manuallyStruckHeaderIDs,
                manuallyStruckQueryParameterIDs: manuallyStruckQueryParameterIDs,
                redactionKeywords: preferences.redactionKeywords,
                redactMatchingHeaders: preferences.redactMatchingHeaders
            )

            httpResponse = result.httpResponse
            httpsResponse = result.httpsResponse
            isSending = false
            updateHistoryResponses(id: historyID, http: result.httpResponse, https: result.httpsResponse)

            // 自动选择有结果的 Tab
            if sendHTTPS && !sendHTTP {
                selectedResponseTab = .https
            } else if sendHTTP && !sendHTTPS {
                selectedResponseTab = .http
            }
        }
    }

    // MARK: - cURL 导出

    func exportCurl() {
        let resolved = VariableEngine.resolve(rawText, environment: selectedEnvironment)
        if let curl = CurlConverter.rawToCurl(
            resolved,
            manuallyStruckIDs: manuallyStruckHeaderIDs,
            manuallyStruckQueryParameterIDs: manuallyStruckQueryParameterIDs,
            redactionKeywords: preferences.redactionKeywords,
            redactMatchingKeywords: preferences.redactMatchingHeaders
        ) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(curl, forType: .string)
        }
    }

    // MARK: - Header Redaction

    func toggleHeaderStrike(_ line: HeaderLine) {
        if manuallyStruckHeaderIDs.contains(line.id) {
            manuallyStruckHeaderIDs.remove(line.id)
        } else {
            manuallyStruckHeaderIDs.insert(line.id)
        }
    }

    func toggleQueryParameterStrike(_ parameter: QueryParameter) {
        if manuallyStruckQueryParameterIDs.contains(parameter.id) {
            manuallyStruckQueryParameterIDs.remove(parameter.id)
        } else {
            manuallyStruckQueryParameterIDs.insert(parameter.id)
        }
    }

    func addRedactionKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = preferences.redactionKeywords.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if !exists {
            preferences.redactionKeywords.append(trimmed)
        }
    }

    func addImportantHeaderName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = preferences.importantHeaderNames.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if !exists {
            preferences.importantHeaderNames.append(trimmed)
        }
    }

    func removeImportantHeaderName(at offsets: IndexSet) {
        preferences.importantHeaderNames.remove(atOffsets: offsets)
    }

    func removeRedactionKeyword(at offsets: IndexSet) {
        preferences.redactionKeywords.remove(atOffsets: offsets)
    }

    // MARK: - Search

    func selectNextRequestSearchMatch() {
        selectedRequestSearchIndex = SearchEngine.nextIndex(
            after: selectedRequestSearchIndex,
            matchCount: requestSearchMatches.count
        )
    }

    func selectPreviousRequestSearchMatch() {
        selectedRequestSearchIndex = SearchEngine.previousIndex(
            before: selectedRequestSearchIndex,
            matchCount: requestSearchMatches.count
        )
    }

    func resetRequestSearchSelection() {
        updateRequestSearchMatches(resetSelection: true)
    }

    func updateRequestSearchMatches(resetSelection: Bool = false) {
        requestSearchTask?.cancel()
        let text = rawText
        let query = requestSearchText
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            requestSearchMatches = []
            selectedRequestSearchIndex = nil
            return
        }

        requestSearchMatches = []
        selectedRequestSearchIndex = nil
        let debounce = searchDebounceNanoseconds
        requestSearchTask = Task.detached(priority: .userInitiated) { [text, query, resetSelection, debounce] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            let matches = SearchWorker.matches(in: text, query: query, source: "request")
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.rawText == text,
                      self.requestSearchText == query else { return }
                self.requestSearchMatches = matches
                self.selectedRequestSearchIndex = self.normalizedSearchIndex(
                    self.selectedRequestSearchIndex,
                    matchCount: matches.count,
                    resetSelection: resetSelection
                )
            }
        }
    }

    func selectNextResponseSearchMatch(matchCount: Int) {
        selectedResponseSearchIndex = SearchEngine.nextIndex(
            after: selectedResponseSearchIndex,
            matchCount: matchCount
        )
    }

    func selectPreviousResponseSearchMatch(matchCount: Int) {
        selectedResponseSearchIndex = SearchEngine.previousIndex(
            before: selectedResponseSearchIndex,
            matchCount: matchCount
        )
    }

    func resetResponseSearchSelection(matchCount: Int) {
        selectedResponseSearchIndex = matchCount == 0 ? nil : 0
    }

    func updateResponseSearchMatches(in text: String, resetSelection: Bool = false) {
        responseSearchTask?.cancel()
        let query = responseSearchText
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            responseSearchSource = ""
            responseSearchMatches = []
            selectedResponseSearchIndex = nil
            return
        }

        let sourceChanged = responseSearchSource != text
        responseSearchSource = text
        responseSearchMatches = []
        selectedResponseSearchIndex = nil
        let debounce = searchDebounceNanoseconds
        responseSearchTask = Task.detached(priority: .userInitiated) { [text, query, resetSelection, sourceChanged, debounce] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            let matches = SearchWorker.matches(in: text, query: query, source: "response")
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.responseSearchSource == text,
                      self.responseSearchText == query else { return }
                self.responseSearchMatches = matches
                self.selectedResponseSearchIndex = self.normalizedSearchIndex(
                    self.selectedResponseSearchIndex,
                    matchCount: matches.count,
                    resetSelection: resetSelection || sourceChanged
                )
            }
        }
    }

    private func normalizedSearchIndex(_ index: Int?, matchCount: Int, resetSelection: Bool) -> Int? {
        guard matchCount > 0 else { return nil }
        if resetSelection { return 0 }
        guard let index else { return 0 }
        return min(max(index, 0), matchCount - 1)
    }

    func focusRequestSearch() {
        activeSearchScope = .request
        requestSearchFocusToken += 1
    }

    func focusResponseSearch() {
        activeSearchScope = .response
        responseSearchFocusToken += 1
    }

    func focusActiveSearch() {
        switch activeSearchScope {
        case .request:
            focusRequestSearch()
        case .response:
            focusResponseSearch()
        }
    }

    func activateRequestSearchScope() {
        activeSearchScope = .request
    }

    func activateResponseSearchScope() {
        activeSearchScope = .response
    }

    // MARK: - Codex

    func runCodexChat() {
        let message = codexDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isCodexRunning else { return }

        let conversation = codexMessages
            .suffix(8)
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        let responseContext = activeResponseForCodex()

        codexDraft = ""
        codexErrorMessage = nil
        isCodexRunning = true
        codexMessages.append(CodexChatMessage(role: .user, content: message))

        let input = CodexRunInput(
            userMessage: message,
            configuredUserPrompt: preferences.codexUserPrompt,
            rawRequest: rawText,
            responseText: responseContext.text,
            responseLabel: responseContext.label,
            conversation: conversation,
            language: appLanguage
        )

        Task {
            do {
                let result = try await codexService.run(input: input)
                applyCodexResult(result)
                codexMessages.append(CodexChatMessage(
                    role: .assistant,
                    content: formattedCodexReply(result)
                ))
                saveAll()
            } catch {
                let message: String
                if let codexError = error as? CodexServiceError {
                    message = codexError.localizedDescription(language: appLanguage)
                } else {
                    message = error.localizedDescription
                }
                codexErrorMessage = message
                codexMessages.append(CodexChatMessage(role: .system, content: message))
            }
            isCodexRunning = false
        }
    }

    func clearRiskHighlights() {
        riskHighlights.removeAll()
    }

    private func applyCodexResult(_ result: CodexRunResult) {
        for keyword in result.redactionKeywords {
            addRedactionKeyword(keyword)
        }

        strikeHeaders(named: result.strikeHeaderNames)
        strikeQueryParameters(named: result.strikeQueryParamNames)

        riskHighlights = result.highlights
            .filter { $0.line > 0 }
            .map {
                RiskHighlight(
                    source: $0.source,
                    line: $0.line,
                    severity: $0.severity,
                    reason: $0.reason
                )
            }
    }

    private func strikeHeaders(named names: [String]) {
        let terms = normalizedTerms(names)
        guard !terms.isEmpty else { return }
        for header in requestHeaderLines where matchesActionTerm(header.name, terms: terms) {
            manuallyStruckHeaderIDs.insert(header.id)
        }
    }

    private func strikeQueryParameters(named names: [String]) {
        let terms = normalizedTerms(names)
        guard !terms.isEmpty else { return }
        for parameter in requestQueryParameters where matchesActionTerm(parameter.name, terms: terms) {
            manuallyStruckQueryParameterIDs.insert(parameter.id)
        }
    }

    private func normalizedTerms(_ names: [String]) -> [String] {
        names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func matchesActionTerm(_ name: String, terms: [String]) -> Bool {
        let normalizedName = name.lowercased()
        return terms.contains { term in
            normalizedName == term || normalizedName.contains(term) || term.contains(normalizedName)
        }
    }

    private func activeResponseForCodex() -> (label: String, text: String) {
        switch selectedResponseTab {
        case .http:
            return ("HTTP", httpResponse?.fullResponseText ?? "")
        case .https:
            return ("HTTPS", httpsResponse?.fullResponseText ?? "")
        case .diff:
            if let httpsResponse {
                return ("HTTPS", httpsResponse.fullResponseText)
            }
            return ("HTTP", httpResponse?.fullResponseText ?? "")
        }
    }

    private func formattedCodexReply(_ result: CodexRunResult) -> String {
        var lines = [result.reply.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }

        if !result.strikeHeaderNames.isEmpty {
            lines.append(tf(.codexReplyStrikeHeaders, result.strikeHeaderNames.joined(separator: ", ")))
        }
        if !result.strikeQueryParamNames.isEmpty {
            lines.append(tf(.codexReplyStrikeQueryParams, result.strikeQueryParamNames.joined(separator: ", ")))
        }
        if !result.redactionKeywords.isEmpty {
            lines.append(tf(.codexReplyNewKeywords, result.redactionKeywords.joined(separator: ", ")))
        }
        if !result.highlights.isEmpty {
            lines.append(tf(.codexReplyHighlightRiskLines, result.highlights.count))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 历史

    func loadFromHistory(_ item: HistoryItem) {
        rawText = item.rawText
        httpResponse = item.httpResponse.map(HTTPResponse.archived)
        httpsResponse = item.httpsResponse.map(HTTPResponse.archived)
        if item.httpsResponse != nil {
            selectedResponseTab = .https
        } else if item.httpResponse != nil {
            selectedResponseTab = .http
        }
        showHistory = false
        updateParseStatus()
        updateRequestSearchMatches(resetSelection: true)
        updateResponseSearchMatches(in: activeResponseForCodex().text, resetSelection: true)
    }

    private func updateHistoryResponses(id: UUID, http: HTTPResponse?, https: HTTPResponse?) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].updateResponses(http: http, https: https)
        PersistenceManager.shared.saveHistory(history)
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        PersistenceManager.shared.saveHistory(history)
    }

    func clearHistory() {
        history.removeAll()
        PersistenceManager.shared.saveHistory(history)
    }
}
