import Foundation
import Testing
@testable import RawSend

/// “无敌”级别的 curl → raw 转换测试。
/// 覆盖 DevTools(bash/cmd)、Postman、Insomnia 常见写法及各种边界情况。
@Suite("cURL import")
struct CurlConverterTests {

    private func base64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
    }

    // MARK: - 基础

    @Test func detectsCurlCommand() {
        #expect(CurlConverter.isCurlCommand("curl https://a.co"))
        #expect(CurlConverter.isCurlCommand("  curl -X GET https://a.co  "))
        #expect(CurlConverter.isCurlCommand("$ curl https://a.co"))
        #expect(CurlConverter.isCurlCommand("/usr/bin/curl https://a.co"))
        #expect(!CurlConverter.isCurlCommand("GET / HTTP/1.1"))
        #expect(!CurlConverter.isCurlCommand("curly fries"))
    }

    @Test func basicGet() throws {
        let r = try #require(CurlConverter.convert("curl https://example.com/api"))
        #expect(r.raw == "GET /api HTTP/1.1\nHost: example.com\n")
        #expect(r.scheme == "https")
    }

    @Test func rootPathDefaultsToSlash() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co"))
        #expect(r.raw.hasPrefix("GET / HTTP/1.1"))
    }

    @Test func explicitMethod() throws {
        let r = try #require(CurlConverter.convert("curl -X DELETE https://example.com/x"))
        #expect(r.raw.hasPrefix("DELETE /x HTTP/1.1"))
    }

    @Test func attachedShortMethod() throws {
        let r = try #require(CurlConverter.convert("curl -XPOST https://h.co/ -d x=1"))
        #expect(r.raw.hasPrefix("POST / HTTP/1.1"))
    }

    // MARK: - Header

    @Test func multipleHeaders() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ -H 'A: 1' -H 'B: 2'"))
        #expect(r.raw.contains("A: 1"))
        #expect(r.raw.contains("B: 2"))
    }

    @Test func adjacentConcatenatedHeader() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ -H\"Content-Type: text/plain\""))
        #expect(r.raw.contains("Content-Type: text/plain"))
    }

    @Test func emptyValueHeaderWithSemicolon() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ -H 'X-Empty;'"))
        #expect(r.raw.contains("X-Empty:"))
    }

    @Test func disabledHeaderIsDropped() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ -H 'Accept:'"))
        #expect(!r.raw.contains("Accept:"))
    }

    // MARK: - Body / 方法推断

    @Test func dataInfersPostAndContentType() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/p -d 'a=1'"))
        #expect(r.raw.hasPrefix("POST /p HTTP/1.1"))
        #expect(r.raw.contains("Content-Type: application/x-www-form-urlencoded"))
        #expect(r.raw.hasSuffix("\n\na=1"))
    }

    @Test func multipleDataJoinedWithAmpersand() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ -d a=1 -d b=2"))
        #expect(r.raw.hasSuffix("\n\na=1&b=2"))
    }

    @Test func dataUrlencodeIsPercentEncoded() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ --data-urlencode 'q=a b&c'"))
        #expect(r.raw.hasSuffix("\n\nq=a%20b%26c"))
    }

    @Test func jsonSetsContentTypeAndAccept() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ --json '{\"a\":1}'"))
        #expect(r.raw.contains("Content-Type: application/json"))
        #expect(r.raw.contains("Accept: application/json"))
        #expect(r.raw.hasSuffix("\n\n{\"a\":1}"))
    }

    @Test func explicitContentTypeNotOverridden() throws {
        let r = try #require(CurlConverter.convert(
            "curl https://h.co/ -H 'Content-Type: application/json' -d '{\"a\":1}'"))
        // 只应出现一次 Content-Type
        let count = r.raw.components(separatedBy: "Content-Type:").count - 1
        #expect(count == 1)
        #expect(r.raw.contains("application/json"))
    }

    @Test func dataBinaryKeepsNewlines() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ --data-binary 'line1\nline2'"))
        #expect(r.raw.contains("line1\nline2"))
    }

    @Test func getFlagMergesDataIntoQuery() throws {
        let r = try #require(CurlConverter.convert("curl -G https://h.co/s -d q=hello -d n=1"))
        #expect(r.raw.hasPrefix("GET /s?q=hello&n=1 HTTP/1.1"))
        #expect(!r.raw.contains("\n\n")) // 无 body
    }

    // MARK: - 认证 / Cookie / UA

    @Test func basicAuthFromUser() throws {
        let r = try #require(CurlConverter.convert("curl -u user:pass https://h.co/"))
        #expect(r.raw.contains("Authorization: Basic \(base64("user:pass"))"))
    }

    @Test func basicAuthFromUrlUserinfo() throws {
        let r = try #require(CurlConverter.convert("curl https://user:pw@h.co/x"))
        #expect(r.raw.contains("Authorization: Basic \(base64("user:pw"))"))
        #expect(r.raw.contains("Host: h.co"))
    }

    @Test func oauthBearer() throws {
        let r = try #require(CurlConverter.convert("curl --oauth2-bearer TOK https://h.co/"))
        #expect(r.raw.contains("Authorization: Bearer TOK"))
    }

    @Test func cookieHeader() throws {
        let r = try #require(CurlConverter.convert("curl -b 'sid=1; t=2' https://h.co/"))
        #expect(r.raw.contains("Cookie: sid=1; t=2"))
    }

    @Test func userAgentHeader() throws {
        let r = try #require(CurlConverter.convert("curl -A 'MyAgent/1.0' https://h.co/"))
        #expect(r.raw.contains("User-Agent: MyAgent/1.0"))
    }

    @Test func refererStripsAuto() throws {
        let r = try #require(CurlConverter.convert("curl -e 'https://ref.co;auto' https://h.co/"))
        #expect(r.raw.contains("Referer: https://ref.co"))
        #expect(!r.raw.contains(";auto"))
    }

    @Test func compressedAddsAcceptEncoding() throws {
        let r = try #require(CurlConverter.convert("curl --compressed https://h.co/"))
        #expect(r.raw.contains("Accept-Encoding: gzip, deflate, br"))
    }

    @Test func headRequest() throws {
        let r = try #require(CurlConverter.convert("curl -I https://h.co/"))
        #expect(r.raw.hasPrefix("HEAD / HTTP/1.1"))
    }

    // MARK: - Multipart

    @Test func multipartForm() throws {
        let r = try #require(CurlConverter.convert("curl -F name=John -F avatar=@pic.png https://h.co/u"))
        #expect(r.raw.hasPrefix("POST /u HTTP/1.1"))
        #expect(r.raw.contains("multipart/form-data; boundary=----RawSendFormBoundary"))
        #expect(r.raw.contains("Content-Disposition: form-data; name=\"name\""))
        #expect(r.raw.contains("filename=\"pic.png\""))
    }

    // MARK: - 分词 / 续行 / 引用

    @Test func backslashLineContinuation() throws {
        let cmd = "curl 'https://h.co/a' \\\n  -H 'X: 1' \\\n  -d 'b=2'"
        let r = try #require(CurlConverter.convert(cmd))
        #expect(r.raw.hasPrefix("POST /a HTTP/1.1"))
        #expect(r.raw.contains("X: 1"))
        #expect(r.raw.hasSuffix("b=2"))
    }

    @Test func caretLineContinuationWindows() throws {
        let cmd = "curl \"https://h.co/w\" ^\n  -H \"X: 1\""
        let r = try #require(CurlConverter.convert(cmd))
        #expect(r.raw.hasPrefix("GET /w HTTP/1.1"))
        #expect(r.raw.contains("X: 1"))
    }

    @Test func ansiCQuoting() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ -H $'X-Tab:\\tval'"))
        #expect(r.raw.contains("X-Tab: val"))
    }

    @Test func doubleQuoteEscapes() throws {
        let r = try #require(CurlConverter.convert("curl \"https://h.co/\" -H \"Auth: \\\"q\\\"\""))
        #expect(r.raw.contains("Auth: \"q\""))
    }

    // MARK: - URL 解析

    @Test func portPreservedAndSchemeHttp() throws {
        let r = try #require(CurlConverter.convert("curl http://h.co:8080/x"))
        #expect(r.raw.contains("Host: h.co:8080"))
        #expect(r.scheme == "http")
    }

    @Test func noSchemeReturnsNilScheme() throws {
        let r = try #require(CurlConverter.convert("curl example.com/p"))
        #expect(r.scheme == nil)
        #expect(r.raw.hasPrefix("GET /p HTTP/1.1"))
        #expect(r.raw.contains("Host: example.com"))
    }

    @Test func templateVariableUrlIsRobust() throws {
        let r = try #require(CurlConverter.convert("curl 'https://{{host}}/api?token={{t}}'"))
        #expect(r.raw.hasPrefix("GET /api?token={{t}} HTTP/1.1"))
        #expect(r.raw.contains("Host: {{host}}"))
    }

    @Test func urlFlag() throws {
        let r = try #require(CurlConverter.convert("curl --url https://h.co/z -H 'A: b'"))
        #expect(r.raw.hasPrefix("GET /z HTTP/1.1"))
        #expect(r.raw.contains("A: b"))
    }

    @Test func longEqualsForm() throws {
        let r = try #require(CurlConverter.convert("curl https://h.co/ --request=PUT --header='X: y'"))
        #expect(r.raw.hasPrefix("PUT / HTTP/1.1"))
        #expect(r.raw.contains("X: y"))
    }

    // MARK: - 未知/忽略 flag

    @Test func ignoredValueFlagsDoNotEatUrl() throws {
        let r = try #require(CurlConverter.convert("curl -s -o out.txt --max-time 5 https://h.co/keep"))
        #expect(r.raw.hasPrefix("GET /keep HTTP/1.1"))
    }

    @Test func booleanClusterFlags() throws {
        let r = try #require(CurlConverter.convert("curl -sSL https://h.co/c"))
        #expect(r.raw.hasPrefix("GET /c HTTP/1.1"))
    }

    // MARK: - 真实 DevTools 风格

    @Test func realWorldDevtoolsBash() throws {
        // 真实的多行粘贴（含反斜杠续行）
        let cmd = "curl 'https://api.example.com/v2/users?page=2' \\\n"
            + "  -H 'accept: application/json, text/plain, */*' \\\n"
            + "  -H 'authorization: Bearer abc.def.ghi' \\\n"
            + "  --data-raw '{\"name\":\"Ann\"}' \\\n"
            + "  --compressed"
        let r = try #require(CurlConverter.convert(cmd))
        #expect(r.raw.hasPrefix("POST /v2/users?page=2 HTTP/1.1"))
        #expect(r.raw.contains("authorization: Bearer abc.def.ghi"))
        #expect(r.raw.hasSuffix("{\"name\":\"Ann\"}"))
        #expect(r.raw.contains("Accept-Encoding: gzip, deflate, br"))
        #expect(r.scheme == "https")
    }

    // MARK: - 回归：非 curl 输入

    @Test func nonCurlReturnsNil() {
        #expect(CurlConverter.convert("GET / HTTP/1.1\nHost: a.co") == nil)
    }
}
