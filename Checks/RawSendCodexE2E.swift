import Foundation

@main
struct RawSendCodexE2E {
    static func main() async {
        let rawRequest = """
        GET /admin/items/detail?appId=13&access_token=secret-token&item_id=5242837&session_id=sid-123 HTTP/1.1
        Host: example.test
        Authorization: Bearer secret
        Cookie: sid=123
        X-Access-Token: jwt-value
        X-Jwt-Token: jwt-value
        X-Service: api.example

        """

        let responseText = """
        HTTP/1.1 200 OK
        Content-Type: application/json

        {"user_id":9703778,"tenant":"demo","debug_token":"server-secret"}
        """

        let input = CodexRunInput(
            userMessage: "划掉所有鉴权相关的参数，并高亮请求和响应里的风险行",
            configuredUserPrompt: AppPreferences.defaultCodexUserPrompt,
            rawRequest: rawRequest,
            responseText: responseText,
            responseLabel: "HTTPS",
            conversation: "",
            language: .simplifiedChinese
        )

        do {
            let result = try await CodexService().run(input: input)
            var failures: [String] = []

            if result.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                failures.append("reply should not be empty")
            }

            let headerNames = Set(result.strikeHeaderNames.map { $0.lowercased() })
            if headerNames.isDisjoint(with: ["authorization", "cookie", "x-access-token", "x-jwt-token"]) {
                failures.append("should strike at least one auth-related header, got \(result.strikeHeaderNames)")
            }

            let queryNames = Set(result.strikeQueryParamNames.map { $0.lowercased() })
            if queryNames.isDisjoint(with: ["access_token", "session_id"]) {
                failures.append("should strike at least one auth-related URL parameter, got \(result.strikeQueryParamNames)")
            }

            if result.highlights.isEmpty {
                failures.append("should return at least one risk highlight")
            }

            if failures.isEmpty {
                print("RawSendCodexE2E passed")
                print("Headers: \(result.strikeHeaderNames.joined(separator: ", "))")
                print("Query params: \(result.strikeQueryParamNames.joined(separator: ", "))")
                print("Highlights: \(result.highlights.count)")
            } else {
                for failure in failures {
                    fputs("FAIL: \(failure)\n", stderr)
                }
                exit(1)
            }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
