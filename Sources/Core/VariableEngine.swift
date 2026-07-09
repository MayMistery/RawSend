import Foundation

/// 变量引擎：处理 {{}} 变量替换
struct VariableEngine {

    /// 替换文本中的所有 {{变量}}
    static func resolve(_ text: String, environment: Environment?) -> String {
        let pattern = #"\{\{([^}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

        // 从后往前替换，避免偏移
        for match in matches.reversed() {
            guard let varRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }

            let varName = String(result[varRange]).trimmingCharacters(in: .whitespaces)
            if let value = resolveVariable(varName, environment: environment) {
                result.replaceSubrange(fullRange, with: value)
            }
        }
        return result
    }

    /// 解析单个变量
    private static func resolveVariable(_ name: String, environment: Environment?) -> String? {
        // 内置动态变量
        if name.hasPrefix("$") {
            return resolveDynamic(name)
        }

        // 环境变量
        return environment?.variables.first(where: { $0.key == name })?.value
    }

    /// 内置动态变量
    private static func resolveDynamic(_ name: String) -> String? {
        switch name {
        case "$timestamp":
            return String(Int(Date().timeIntervalSince1970))
        case "$uuid":
            return UUID().uuidString.lowercased()
        case "$random_int":
            return String(Int.random(in: 0...99999))
        case "$date":
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: Date())
        default:
            // {{$base64:content}}
            if name.hasPrefix("$base64:") {
                let content = String(name.dropFirst("$base64:".count))
                return Data(content.utf8).base64EncodedString()
            }
            return nil
        }
    }

    /// 提取文本中所有变量名
    static func extractVariables(_ text: String) -> [String] {
        let pattern = #"\{\{([^}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// 检查哪些变量未定义
    static func undefinedVariables(_ text: String, environment: Environment?) -> [String] {
        let vars = extractVariables(text)
        return vars.filter { name in
            if name.hasPrefix("$") {
                // 内置动态变量都有定义
                return false
            }
            return environment?.variables.first(where: { $0.key == name }) == nil
        }
    }
}
