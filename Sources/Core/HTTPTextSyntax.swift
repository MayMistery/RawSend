import Foundation

enum HTTPTextSyntax {
    static func firstTokenRange(in text: String) -> NSRange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let firstLine = source.lineRange(for: NSRange(location: 0, length: 0))
        var end = firstLine.location
        while end < firstLine.location + firstLine.length {
            let character = source.character(at: end)
            if character == unichar(32) || character == unichar(9) || character == unichar(10) || character == unichar(13) {
                break
            }
            end += 1
        }
        guard end > firstLine.location else { return nil }
        return NSRange(location: firstLine.location, length: end - firstLine.location)
    }

    static func statusCodeRange(in text: String) -> (range: NSRange, code: Int)? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let firstLineRange = source.lineRange(for: NSRange(location: 0, length: 0))
        let firstLine = source.substring(with: firstLineRange)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let code = Int(parts[1]) else { return nil }

        let firstTokenLength = (parts[0] as NSString).length
        var location = firstLineRange.location + firstTokenLength
        while location < firstLineRange.location + firstLineRange.length {
            let character = source.character(at: location)
            if character != unichar(32) && character != unichar(9) {
                break
            }
            location += 1
        }

        let codeLength = (parts[1] as NSString).length
        guard location + codeLength <= source.length else { return nil }
        return (NSRange(location: location, length: codeLength), code)
    }

    static func headerNameRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        guard source.length > 0 else { return [] }

        var result: [NSRange] = []
        var location = 0
        var lineNumber = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let rawLine = source.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            defer {
                let nextLocation = lineRange.location + lineRange.length
                location = max(nextLocation, location + 1)
                lineNumber += 1
            }

            if lineNumber == 0 {
                continue
            }
            if line.isEmpty {
                break
            }
            guard let colonIndex = line.firstIndex(of: ":") else {
                continue
            }
            let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let nameLength = (name as NSString).length
            result.append(NSRange(location: lineRange.location, length: nameLength))
        }
        return result
    }

    static func jsonTokens(in text: String, maximumTokens: Int = JSONSyntaxHighlighter.defaultMaximumTokens) -> [JSONSyntaxToken] {
        guard let bodyRange = HTTPMessageRanges.bodyRange(in: text) else { return [] }
        return JSONSyntaxHighlighter.tokenRanges(in: text, range: bodyRange, maximumTokens: maximumTokens)
    }

    static func htmlTokens(in text: String, maximumTokens: Int = HTMLSyntaxHighlighter.defaultMaximumTokens) -> [HTMLSyntaxToken] {
        guard let bodyRange = HTTPMessageRanges.bodyRange(in: text),
              isHTMLResponse(text, bodyRange: bodyRange) else { return [] }
        return HTMLSyntaxHighlighter.tokenRanges(in: text, range: bodyRange, maximumTokens: maximumTokens)
    }

    static func htmlPreviewBody(in text: String) -> String? {
        let source = text as NSString
        guard let bodyRange = HTTPMessageRanges.bodyRange(in: text),
              isHTMLResponse(text, bodyRange: bodyRange) else { return nil }
        let body = source.substring(with: bodyRange)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return body
    }

    private static func isHTMLResponse(_ text: String, bodyRange: NSRange) -> Bool {
        if let contentType = headerValue(named: "Content-Type", in: text) {
            let normalized = contentType.lowercased()
            if normalized.contains("text/html") || normalized.contains("application/xhtml+xml") {
                return true
            }
        }

        let source = text as NSString
        let body = source.substring(with: bodyRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return body.hasPrefix("<!doctype html")
            || body.hasPrefix("<html")
            || body.hasPrefix("<head")
            || body.hasPrefix("<body")
    }

    private static func headerValue(named headerName: String, in text: String) -> String? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let target = headerName.lowercased()
        var location = 0
        var lineNumber = 0

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let rawLine = source.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            defer {
                let nextLocation = lineRange.location + lineRange.length
                location = max(nextLocation, location + 1)
                lineNumber += 1
            }

            if lineNumber == 0 {
                continue
            }
            if line.isEmpty {
                break
            }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            guard name == target else { continue }
            return String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
