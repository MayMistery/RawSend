import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "中文"
        case .spanish: return "Español"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AppLanguage(rawValue: rawValue) ?? .english
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum L10nKey: String, CaseIterable {
    case add
    case addHeader
    case addVariable
    case addFilterKeywordHelp
    case actionStatus
    case builtInVariables
    case bodyBytes
    case clear
    case clearHighlights
    case clearSearch
    case clearRequest
    case codexConsole
    case codexRunning
    case codexCommandPlaceholder
    case codexAnalyzing
    case codexFirstInstruction
    case codexMissingCLI
    case codexLaunchFailed
    case codexExecutionFailed
    case codexNoStructuredOutput
    case codexParseFailed
    case codexReplyHighlightRiskLines
    case codexReplyNewKeywords
    case codexReplyStrikeHeaders
    case codexReplyStrikeQueryParams
    case conversation
    case copyErrorInfo
    case defaultHeaders
    case defaultHeadersDescription
    case diffNeedsBothResponses
    case diffHasRequestError
    case diffResponsesIdentical
    case diffStatusSame
    case diffStatusDifferent
    case diffDifferences
    case environment
    case environmentName
    case environments
    case export
    case exportCurlHelp
    case filterKeywords
    case filterSensitiveHeaders
    case filterSensitiveHeadersHelp
    case fieldKey
    case fieldName
    case fieldValue
    case follow
    case followRedirects
    case followRedirectsHelp
    case followLocation
    case general
    case globalDefaultHeaders
    case headersStruck
    case history
    case historyEmpty
    case historyLimitPrefix
    case historyLimitSuffix
    case hostLabel
    case hostMissing
    case ignoreTLSErrors
    case importantHeadersSection
    case includeDefaultHeadersInCurl
    case invalidRawRequest
    case invalidURL
    case language
    case network
    case noImportantHeaderHit
    case noMatches
    case none
    case openLogFile
    case queryParameters
    case ready
    case request
    case requestInvalid
    case requestImportantHeaders
    case requestReady
    case requestSearchPlaceholder
    case requestTimeout
    case requestTitle
    case resetDefault
    case response
    case responseEmpty
    case responseLoaded
    case responsePreview
    case responseRaw
    case responseSearchPlaceholder
    case responseWillAppear
    case riskHighlights
    case riskLines
    case search
    case searchRequest
    case searchResponse
    case searchHistoryPlaceholder
    case selectEnvironment
    case send
    case settingsHelp
    case clearEditor
    case switchEnvironment
    case struckHeadersMetric
    case struckQueryParameters
    case timeoutSeconds
    case userPrompt
    case variables
    case variablesUndefined
    case addHeaderNameAsKeyword
    case addHeaderValueAsKeyword
    case addQueryParameterNameAsKeyword
    case addQueryParameterValueAsKeyword
    case addSelectedHeaderAsImportant
    case addSelectedTextAsKeyword
    case strikeCurrentHeader
    case restoreCurrentHeader
    case strikeCurrentQueryParameter
    case restoreCurrentQueryParameter
    case previousMatch
    case nextMatch
    case headerNamePlaceholder
    case hideValueHelp
    case newEnvironmentName
    case showValueHelp
}

struct Localizer {
    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        table[language]?[key] ?? table[.english]?[key] ?? key.rawValue
    }

    static func format(_ key: L10nKey, language: AppLanguage, _ arguments: CVarArg...) -> String {
        format(key, language: language, arguments: arguments)
    }

    static func format(_ key: L10nKey, language: AppLanguage, arguments: [CVarArg]) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    static func missingKeys(for language: AppLanguage) -> [L10nKey] {
        let translations = table[language] ?? [:]
        return L10nKey.allCases.filter { translations[$0] == nil }
    }

    private static let table: [AppLanguage: [L10nKey: String]] = [
        .english: [
            .add: "Add",
            .addHeader: "Add Header",
            .addVariable: "Add variable",
            .addFilterKeywordHelp: "Add filter keyword",
            .actionStatus: "Action Status",
            .builtInVariables: "Built-in: {{$timestamp}} {{$uuid}} {{$random_int}} {{$date}} {{$base64:...}}",
            .bodyBytes: "Body: %dB",
            .clear: "Clear",
            .clearHighlights: "Clear highlights",
            .clearSearch: "Clear search",
            .clearRequest: "Clear (⌘L)",
            .codexConsole: "Codex Console",
            .codexRunning: "Codex is running",
            .codexCommandPlaceholder: "Tell Codex what to do",
            .codexAnalyzing: "Analyzing the current request and response",
            .codexFirstInstruction: "Waiting for the first instruction",
            .codexMissingCLI: "Local codex CLI was not found. Install codex or make sure it is available in PATH, /opt/homebrew/bin, or /usr/local/bin.",
            .codexLaunchFailed: "Failed to launch codex: %@",
            .codexExecutionFailed: "codex failed (exit %d): %@",
            .codexNoStructuredOutput: "codex did not write structured output.",
            .codexParseFailed: "Failed to parse codex output: %@",
            .codexReplyHighlightRiskLines: "Risk lines highlighted: %d",
            .codexReplyNewKeywords: "New keywords: %@",
            .codexReplyStrikeHeaders: "Struck Headers: %@",
            .codexReplyStrikeQueryParams: "Struck URL parameters: %@",
            .conversation: "Conversation",
            .copyErrorInfo: "Copy error info",
            .defaultHeaders: "Default Headers",
            .defaultHeadersDescription: "Appended automatically when sending; explicit request headers with the same name are not overwritten.",
            .diffNeedsBothResponses: "Two responses are required for comparison",
            .diffHasRequestError: "A request error exists; comparison is unavailable",
            .diffResponsesIdentical: "Responses are identical",
            .diffStatusSame: "same",
            .diffStatusDifferent: "different",
            .diffDifferences: "Status %@ | %d differences",
            .environment: "Environment",
            .environmentName: "Environment name",
            .environments: "Environments",
            .export: "Export",
            .exportCurlHelp: "Export as cURL (⌘⇧C)",
            .filterKeywords: "Filter keywords",
            .filterSensitiveHeaders: "Filter sensitive Headers",
            .filterSensitiveHeadersHelp: "Strike by keyword and filter Header values when sending",
            .fieldKey: "Key",
            .fieldName: "Name",
            .fieldValue: "Value",
            .follow: "Follow",
            .followRedirects: "Follow redirects",
            .followRedirectsHelp: "Automatically follow 3xx Location when sending",
            .followLocation: "Follow Location: %@",
            .general: "General",
            .globalDefaultHeaders: "Global default Headers",
            .headersStruck: "Struck Headers",
            .history: "History",
            .historyEmpty: "No history yet",
            .historyLimitPrefix: "Keep up to",
            .historyLimitSuffix: "items",
            .hostLabel: "Host:",
            .hostMissing: "Not detected",
            .ignoreTLSErrors: "Ignore TLS certificate errors",
            .importantHeadersSection: "Important Header display",
            .includeDefaultHeadersInCurl: "Include default headers in cURL export",
            .invalidRawRequest: "Unable to parse raw request",
            .invalidURL: "Invalid URL: %@",
            .language: "Language",
            .network: "Network",
            .noImportantHeaderHit: "No important Header matched",
            .noMatches: "No matches",
            .none: "None",
            .openLogFile: "Open log file",
            .queryParameters: "URL parameters",
            .ready: "Ready",
            .request: "Request",
            .requestInvalid: "Invalid",
            .requestImportantHeaders: "Important request Headers",
            .requestReady: "Ready",
            .requestSearchPlaceholder: "Search request",
            .requestTimeout: "Request timeout",
            .requestTitle: "Request",
            .resetDefault: "Reset default",
            .response: "Response",
            .responseEmpty: "Empty",
            .responseLoaded: "Loaded",
            .responsePreview: "Preview",
            .responseRaw: "Raw",
            .responseSearchPlaceholder: "Search response",
            .responseWillAppear: "%@ response will appear here",
            .riskHighlights: "Risk highlights",
            .riskLines: "Risk lines",
            .search: "Search",
            .searchRequest: "Search request",
            .searchResponse: "Search response",
            .searchHistoryPlaceholder: "Search history...",
            .selectEnvironment: "Select an environment",
            .send: "Send",
            .settingsHelp: "Settings (⌘,)",
            .clearEditor: "Clear editor",
            .switchEnvironment: "Switch environment",
            .struckHeadersMetric: "Headers",
            .struckQueryParameters: "Struck URL parameters",
            .timeoutSeconds: "seconds",
            .userPrompt: "User Prompt",
            .variables: "Variables: %d",
            .variablesUndefined: "(%d undefined)",
            .addHeaderNameAsKeyword: "Add Header name to filter keywords",
            .addHeaderValueAsKeyword: "Add Header value to filter keywords",
            .addQueryParameterNameAsKeyword: "Add URL parameter name to filter keywords",
            .addQueryParameterValueAsKeyword: "Add URL parameter value to filter keywords",
            .addSelectedHeaderAsImportant: "Add selected Header to important display",
            .addSelectedTextAsKeyword: "Add selected text to filter keywords",
            .strikeCurrentHeader: "Strike current Header",
            .restoreCurrentHeader: "Restore current Header",
            .strikeCurrentQueryParameter: "Strike current URL parameter",
            .restoreCurrentQueryParameter: "Restore current URL parameter",
            .previousMatch: "Previous match",
            .nextMatch: "Next match",
            .headerNamePlaceholder: "Header name",
            .hideValueHelp: "Hide value",
            .newEnvironmentName: "New Env",
            .showValueHelp: "Show value",
        ],
        .simplifiedChinese: [
            .add: "添加",
            .addHeader: "添加 Header",
            .addVariable: "添加变量",
            .addFilterKeywordHelp: "添加过滤关键词",
            .actionStatus: "动作状态",
            .builtInVariables: "内置: {{$timestamp}} {{$uuid}} {{$random_int}} {{$date}} {{$base64:...}}",
            .bodyBytes: "Body: %dB",
            .clear: "清空",
            .clearHighlights: "清除高亮",
            .clearSearch: "清空搜索",
            .clearRequest: "清空 (⌘L)",
            .codexConsole: "Codex 控制台",
            .codexRunning: "Codex 正在运行",
            .codexCommandPlaceholder: "向 Codex 下达操作指令",
            .codexAnalyzing: "正在分析当前请求和响应",
            .codexFirstInstruction: "等待第一条指令",
            .codexMissingCLI: "未找到本地 codex CLI。请确认已安装并且 codex 在 PATH、/opt/homebrew/bin 或 /usr/local/bin 下。",
            .codexLaunchFailed: "启动 codex 失败：%@",
            .codexExecutionFailed: "codex 执行失败（exit %d）：%@",
            .codexNoStructuredOutput: "codex 没有写出结构化结果。",
            .codexParseFailed: "无法解析 codex 输出：%@",
            .codexReplyHighlightRiskLines: "高亮风险行: %d",
            .codexReplyNewKeywords: "新增关键词: %@",
            .codexReplyStrikeHeaders: "划掉 Headers: %@",
            .codexReplyStrikeQueryParams: "划掉 URL 参数: %@",
            .conversation: "会话",
            .copyErrorInfo: "复制错误信息",
            .defaultHeaders: "默认头",
            .defaultHeadersDescription: "发送时自动追加，不覆盖请求中已显式写的同名头",
            .diffNeedsBothResponses: "需要两个响应才能对比",
            .diffHasRequestError: "存在请求错误，无法对比",
            .diffResponsesIdentical: "响应完全相同",
            .diffStatusSame: "相同",
            .diffStatusDifferent: "不同",
            .diffDifferences: "状态码%@ | %d 处差异",
            .environment: "环境",
            .environmentName: "环境名称",
            .environments: "环境变量",
            .export: "导出",
            .exportCurlHelp: "导出为 cURL (⌘⇧C)",
            .filterKeywords: "过滤关键词",
            .filterSensitiveHeaders: "过滤敏感 Headers",
            .filterSensitiveHeadersHelp: "按关键词划掉并在发送时过滤 Header",
            .fieldKey: "Key",
            .fieldName: "Name",
            .fieldValue: "Value",
            .follow: "跟随",
            .followRedirects: "跟随重定向",
            .followRedirectsHelp: "发送时自动跟随 3xx Location",
            .followLocation: "跟随 Location: %@",
            .general: "通用",
            .globalDefaultHeaders: "全局默认 Headers",
            .headersStruck: "已划 Headers",
            .history: "历史记录",
            .historyEmpty: "暂无历史记录",
            .historyLimitPrefix: "最多保留",
            .historyLimitSuffix: "条",
            .hostLabel: "Host:",
            .hostMissing: "未检测到",
            .ignoreTLSErrors: "忽略 TLS 证书错误",
            .importantHeadersSection: "重点 Header 展示",
            .includeDefaultHeadersInCurl: "cURL 导出时包含默认头",
            .invalidRawRequest: "无法解析请求报文",
            .invalidURL: "无效的 URL: %@",
            .language: "Language / 语言",
            .network: "网络",
            .noImportantHeaderHit: "未命中重点 Header",
            .noMatches: "无匹配结果",
            .none: "暂无",
            .openLogFile: "打开日志文件",
            .queryParameters: "URL 参数",
            .ready: "就绪",
            .request: "请求",
            .requestInvalid: "无效",
            .requestImportantHeaders: "请求重点 Headers",
            .requestReady: "就绪",
            .requestSearchPlaceholder: "搜索请求",
            .requestTimeout: "请求超时",
            .requestTitle: "请求",
            .resetDefault: "恢复默认",
            .response: "响应",
            .responseEmpty: "空",
            .responseLoaded: "已载入",
            .responsePreview: "预览",
            .responseRaw: "Raw",
            .responseSearchPlaceholder: "搜索响应",
            .responseWillAppear: "%@ 响应将在此显示",
            .riskHighlights: "风险高亮",
            .riskLines: "风险行",
            .search: "搜索",
            .searchRequest: "搜索请求",
            .searchResponse: "搜索响应",
            .searchHistoryPlaceholder: "搜索历史...",
            .selectEnvironment: "选择一个环境",
            .send: "发送",
            .settingsHelp: "设置 (⌘,)",
            .clearEditor: "清空编辑区",
            .switchEnvironment: "切换环境",
            .struckHeadersMetric: "Headers",
            .struckQueryParameters: "已划 URL 参数",
            .timeoutSeconds: "秒",
            .userPrompt: "用户 Prompt",
            .variables: "变量: %d个",
            .variablesUndefined: "(%d个未定义)",
            .addHeaderNameAsKeyword: "把 Header 名加入过滤关键词",
            .addHeaderValueAsKeyword: "把 Header 值加入过滤关键词",
            .addQueryParameterNameAsKeyword: "把 URL 参数名加入过滤关键词",
            .addQueryParameterValueAsKeyword: "把 URL 参数值加入过滤关键词",
            .addSelectedHeaderAsImportant: "把选中 Header 加入重点展示",
            .addSelectedTextAsKeyword: "把选中文本加入过滤关键词",
            .strikeCurrentHeader: "划掉当前 Header",
            .restoreCurrentHeader: "恢复当前 Header",
            .strikeCurrentQueryParameter: "划掉当前 URL 参数",
            .restoreCurrentQueryParameter: "恢复当前 URL 参数",
            .previousMatch: "上一个匹配",
            .nextMatch: "下一个匹配",
            .headerNamePlaceholder: "Header 名称",
            .hideValueHelp: "点击隐藏值",
            .newEnvironmentName: "新环境",
            .showValueHelp: "点击取消隐藏",
        ],
        .spanish: [
            .add: "Agregar",
            .addHeader: "Agregar Header",
            .addVariable: "Agregar variable",
            .addFilterKeywordHelp: "Agregar keyword de filtro",
            .actionStatus: "Estado de acciones",
            .builtInVariables: "Integradas: {{$timestamp}} {{$uuid}} {{$random_int}} {{$date}} {{$base64:...}}",
            .bodyBytes: "Body: %dB",
            .clear: "Limpiar",
            .clearHighlights: "Limpiar resaltados",
            .clearSearch: "Limpiar búsqueda",
            .clearRequest: "Limpiar (⌘L)",
            .codexConsole: "Consola Codex",
            .codexRunning: "Codex en ejecución",
            .codexCommandPlaceholder: "Indica a Codex qué hacer",
            .codexAnalyzing: "Analizando la request y la response actuales",
            .codexFirstInstruction: "Esperando la primera instrucción",
            .codexMissingCLI: "No se encontró el CLI local de codex. Instala codex o asegúrate de que esté disponible en PATH, /opt/homebrew/bin o /usr/local/bin.",
            .codexLaunchFailed: "No se pudo iniciar codex: %@",
            .codexExecutionFailed: "codex falló (exit %d): %@",
            .codexNoStructuredOutput: "codex no escribió salida estructurada.",
            .codexParseFailed: "No se pudo parsear la salida de codex: %@",
            .codexReplyHighlightRiskLines: "Líneas de riesgo resaltadas: %d",
            .codexReplyNewKeywords: "Nuevas keywords: %@",
            .codexReplyStrikeHeaders: "Headers tachados: %@",
            .codexReplyStrikeQueryParams: "Parámetros URL tachados: %@",
            .conversation: "Conversación",
            .copyErrorInfo: "Copiar error",
            .defaultHeaders: "Headers por defecto",
            .defaultHeadersDescription: "Se agregan automáticamente al enviar; no sobrescriben Headers ya escritos en la request.",
            .diffNeedsBothResponses: "Se necesitan dos responses para comparar",
            .diffHasRequestError: "Hay un error de request; no se puede comparar",
            .diffResponsesIdentical: "Las responses son idénticas",
            .diffStatusSame: "igual",
            .diffStatusDifferent: "distinto",
            .diffDifferences: "Status %@ | %d diferencias",
            .environment: "Entorno",
            .environmentName: "Nombre del entorno",
            .environments: "Entornos",
            .export: "Exportar",
            .exportCurlHelp: "Exportar como cURL (⌘⇧C)",
            .filterKeywords: "Keywords de filtro",
            .filterSensitiveHeaders: "Filtrar Headers sensibles",
            .filterSensitiveHeadersHelp: "Tachar por keyword y filtrar Header / parámetros URL al enviar",
            .fieldKey: "Key",
            .fieldName: "Nombre",
            .fieldValue: "Valor",
            .follow: "Seguir",
            .followRedirects: "Seguir redirects",
            .followRedirectsHelp: "Seguir automáticamente Location 3xx al enviar",
            .followLocation: "Seguir Location: %@",
            .general: "General",
            .globalDefaultHeaders: "Headers globales por defecto",
            .headersStruck: "Headers tachados",
            .history: "Historial",
            .historyEmpty: "Sin historial",
            .historyLimitPrefix: "Guardar hasta",
            .historyLimitSuffix: "items",
            .hostLabel: "Host:",
            .hostMissing: "No detectado",
            .ignoreTLSErrors: "Ignorar errores de certificado TLS",
            .importantHeadersSection: "Visualización de Headers importantes",
            .includeDefaultHeadersInCurl: "Incluir headers por defecto en exportación cURL",
            .invalidRawRequest: "No se pudo parsear la raw request",
            .invalidURL: "URL inválida: %@",
            .language: "Language / Idioma",
            .network: "Red",
            .noImportantHeaderHit: "No se encontró ningún Header importante",
            .noMatches: "Sin resultados",
            .none: "Ninguno",
            .openLogFile: "Abrir log",
            .queryParameters: "Parámetros URL",
            .ready: "Listo",
            .request: "Request",
            .requestInvalid: "Inválida",
            .requestImportantHeaders: "Headers importantes de la request",
            .requestReady: "Lista",
            .requestSearchPlaceholder: "Buscar en request",
            .requestTimeout: "Timeout de request",
            .requestTitle: "Request",
            .resetDefault: "Restaurar default",
            .response: "Response",
            .responseEmpty: "Vacía",
            .responseLoaded: "Cargada",
            .responsePreview: "Vista",
            .responseRaw: "Raw",
            .responseSearchPlaceholder: "Buscar en response",
            .responseWillAppear: "La response %@ aparecerá aquí",
            .riskHighlights: "Resaltados de riesgo",
            .riskLines: "Líneas de riesgo",
            .search: "Buscar",
            .searchRequest: "Buscar request",
            .searchResponse: "Buscar response",
            .searchHistoryPlaceholder: "Buscar historial...",
            .selectEnvironment: "Selecciona un entorno",
            .send: "Enviar",
            .settingsHelp: "Settings (⌘,)",
            .clearEditor: "Limpiar editor",
            .switchEnvironment: "Cambiar entorno",
            .struckHeadersMetric: "Headers",
            .struckQueryParameters: "Parámetros URL tachados",
            .timeoutSeconds: "segundos",
            .userPrompt: "User Prompt",
            .variables: "Variables: %d",
            .variablesUndefined: "(%d sin definir)",
            .addHeaderNameAsKeyword: "Agregar nombre del Header a keywords de filtro",
            .addHeaderValueAsKeyword: "Agregar valor del Header a keywords de filtro",
            .addQueryParameterNameAsKeyword: "Agregar nombre del parámetro URL a keywords de filtro",
            .addQueryParameterValueAsKeyword: "Agregar valor del parámetro URL a keywords de filtro",
            .addSelectedHeaderAsImportant: "Agregar Header seleccionado a importantes",
            .addSelectedTextAsKeyword: "Agregar texto seleccionado a keywords de filtro",
            .strikeCurrentHeader: "Tachar Header actual",
            .restoreCurrentHeader: "Restaurar Header actual",
            .strikeCurrentQueryParameter: "Tachar parámetro URL actual",
            .restoreCurrentQueryParameter: "Restaurar parámetro URL actual",
            .previousMatch: "Resultado anterior",
            .nextMatch: "Resultado siguiente",
            .headerNamePlaceholder: "Nombre del Header",
            .hideValueHelp: "Ocultar valor",
            .newEnvironmentName: "Nuevo entorno",
            .showValueHelp: "Mostrar valor",
        ],
    ]
}
