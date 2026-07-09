import Foundation

struct CodexPrompt {
    static let outputSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["reply", "strike_header_names", "strike_query_param_names", "redaction_keywords", "highlights"],
      "properties": {
        "reply": {
          "type": "string",
          "description": "Short response for the RawSend user in the requested UI language. Do not repeat long secrets."
        },
        "strike_header_names": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Header names that RawSend should strike and omit when sending."
        },
        "strike_query_param_names": {
          "type": "array",
          "items": { "type": "string" },
          "description": "URL query parameter names that RawSend should strike and omit when sending."
        },
        "redaction_keywords": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Extra keyword filters RawSend should add for future header and URL parameter redaction."
        },
        "highlights": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["source", "line", "severity", "reason"],
            "properties": {
              "source": { "type": "string", "enum": ["request", "response"] },
              "line": { "type": "integer", "minimum": 1 },
              "severity": { "type": "string", "enum": ["low", "medium", "high"] },
              "reason": { "type": "string" }
            }
          }
        }
      }
    }
    """

    static func makePrompt(input: CodexRunInput) -> String {
        let configuredPrompt = input.configuredUserPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt = configuredPrompt.isEmpty ? AppPreferences.defaultCodexUserPrompt : configuredPrompt
        let conversation = input.conversation
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = promptLabels(language: input.language)
        let responseBlock = input.responseText.isEmpty ? labels.emptyResponse : input.responseText
        let conversationBlock = conversation.isEmpty ? "" : """
        \(labels.recentConversation)
        \(conversation)

        """

        return """
        \(systemPrompt(language: input.language))

        \(labels.configuredUserPrompt)
        \(userPrompt)

        \(labels.currentChatMessage)
        \(input.userMessage)

        \(conversationBlock)
        \(labels.currentRequest)
        ```http
        \(input.rawRequest)
        ```

        \(labels.currentResponse) (\(input.responseLabel)):
        ```http
        \(responseBlock)
        ```

        \(labels.outputInstruction)
        """
    }

    private static func systemPrompt(language: AppLanguage) -> String {
        switch language {
        case .english:
            return """
            You are RawSend's local security analysis assistant. Analyze the current Raw HTTP request and response, identify risky parameters, and return structured JSON telling RawSend which UI actions to apply directly.

            Available actions:
            1. strike_header_names: Header names. RawSend matches by name, strikes those Headers, and omits them when sending or exporting cURL.
            2. strike_query_param_names: URL query parameter names. RawSend matches by name, strikes those parameters, and omits them when sending or exporting cURL.
            3. redaction_keywords: Reusable keywords such as token, auth, cookie, jwt, session, secret, csrf, credential, authorization. RawSend later uses them to strike Header and URL parameters.
            4. highlights: Request or response line numbers to highlight, starting at 1. Request lines refer to the raw request editor; response lines refer to the full response text, including status line, Headers, blank line, and body.

            Rules:
            - If the user asks to strike all auth-related parameters, prioritize Headers like Authorization, Cookie, X-Auth-Token, X-Access-Token, X-Jwt-Token, X-Session-Id, and URL parameters like access_token, auth_token, token, jwt, session, cookie, sid, csrf, credential.
            - Do not repeat long tokens, cookies, or JWTs in reply or reason; describe only field names and risk types.
            - Focus on auth credentials, user identity, tenant, environment, routing, service identifiers, trace IDs, forwarding/proxy fields, replay-related fields, and response-side stack traces, sensitive data, or authorization bypass clues.
            - Response Headers do not need important Header display; mark risky response lines only in highlights.
            - reply and highlights.reason must be written in English. Keep HTTP, Header, URL, cURL, token, cookie, JWT, and Codex as technical terms when natural.
            - Output only JSON that conforms to the JSON Schema. Do not output Markdown.
            """
        case .simplifiedChinese:
            return """
            你是 RawSend 的本地安全分析助手。你的任务是分析当前 Raw HTTP 请求和响应，识别风险参数，并通过结构化 JSON 告诉 RawSend 应该直接执行哪些界面动作。

            你可以使用的动作：
            1. strike_header_names：填写 Header 名。RawSend 会按名称匹配并划掉这些 Header，发送请求和导出 cURL 时不会带上。
            2. strike_query_param_names：填写 URL query 参数名。RawSend 会按名称匹配并划掉这些参数，发送请求和导出 cURL 时不会带上。
            3. redaction_keywords：填写可复用关键词，例如 token、auth、cookie、jwt、session、secret、csrf、credential、authorization。RawSend 后续会按关键词划掉 Header 和 URL 参数。
            4. highlights：填写需要高亮的请求或响应行号，行号从 1 开始。请求行号对应原始请求编辑器；响应行号对应完整响应文本，包括状态行、响应头、空行和响应体。

            规则：
            - 用户让你“划掉所有鉴权相关参数”时，优先输出 Authorization、Cookie、X-Auth-Token、X-Access-Token、X-Jwt-Token、X-Session-Id 这类 Header，以及 access_token、auth_token、token、jwt、session、cookie、sid、csrf、credential 这类 URL 参数。
            - 不要把长 token、cookie、JWT 原样复述到 reply 或 reason 中；只描述字段名和风险类型。
            - 重点关注鉴权凭证、用户身份、租户、环境、路由、服务标识、trace、代理转发、重放相关字段，以及响应中的错误堆栈、敏感数据、越权线索。
            - 响应不需要重点 Header 展示；只在 highlights 中标注风险行。
            - reply 和 highlights.reason 必须使用简体中文；HTTP、Header、URL、cURL、token、cookie、JWT、Codex 这类技术词按上下文保留。
            - 只输出符合 JSON Schema 的最终结果，不要输出 Markdown。
            """
        case .spanish:
            return """
            Eres el asistente local de análisis de seguridad de RawSend. Analiza la Raw HTTP request y la response actuales, identifica parámetros de riesgo y devuelve JSON estructurado indicando qué acciones de UI debe aplicar RawSend directamente.

            Acciones disponibles:
            1. strike_header_names: nombres de Header. RawSend los empareja por nombre, tacha esos Headers y los omite al enviar o exportar cURL.
            2. strike_query_param_names: nombres de parámetros URL query. RawSend los empareja por nombre, los tacha y los omite al enviar o exportar cURL.
            3. redaction_keywords: keywords reutilizables como token, auth, cookie, jwt, session, secret, csrf, credential, authorization. RawSend las usará después para tachar Header y parámetros URL.
            4. highlights: números de línea de request o response que se deben resaltar, empezando en 1. Las líneas de request corresponden al editor raw; las líneas de response corresponden al texto completo de la response, incluyendo status line, Headers, línea en blanco y body.

            Reglas:
            - Si el usuario pide tachar todos los parámetros relacionados con autenticación, prioriza Headers como Authorization, Cookie, X-Auth-Token, X-Access-Token, X-Jwt-Token, X-Session-Id, y parámetros URL como access_token, auth_token, token, jwt, session, cookie, sid, csrf, credential.
            - No repitas tokens, cookies ni JWT largos en reply o reason; describe solo nombres de campo y tipos de riesgo.
            - Enfócate en credenciales de auth, identidad de usuario, tenant, entorno, rutas, identificadores de servicio, trace IDs, campos de forwarding/proxy, campos de replay, y en la response stack traces, datos sensibles o señales de bypass de autorización.
            - Los Headers de response no necesitan visualización de Header importante; marca líneas de response riesgosas solo en highlights.
            - reply y highlights.reason deben estar escritos en español. Conserva HTTP, Header, URL, cURL, token, cookie, JWT y Codex como términos técnicos cuando sea natural.
            - Devuelve solo JSON conforme al JSON Schema. No devuelvas Markdown.
            """
        }
    }

    private static func promptLabels(language: AppLanguage) -> (
        configuredUserPrompt: String,
        currentChatMessage: String,
        recentConversation: String,
        currentRequest: String,
        currentResponse: String,
        outputInstruction: String,
        emptyResponse: String
    ) {
        switch language {
        case .english:
            return (
                "Configured user Prompt:",
                "Current chat message:",
                "Recent conversation:",
                "Current request:",
                "Current response",
                "Output JSON from the current context above.",
                "<empty response>"
            )
        case .simplifiedChinese:
            return (
                "用户配置 Prompt:",
                "当前聊天消息:",
                "最近对话:",
                "当前请求:",
                "当前响应",
                "请基于上面的当前上下文输出 JSON。",
                "<空响应>"
            )
        case .spanish:
            return (
                "Prompt de usuario configurado:",
                "Mensaje actual del chat:",
                "Conversación reciente:",
                "Request actual:",
                "Response actual",
                "Genera JSON basándote en el contexto actual anterior.",
                "<response vacía>"
            )
        }
    }
}
