import Foundation

struct HeaderInspector {
    static let defaultRedactionKeywords = ["token", "auth", "cookie"]
    static let defaultImportantHeaderNames: [String] = []

    static func makeHeaderLines(
        from headers: [(String, String)],
        manuallyStruckIDs: Set<HeaderLine.ID>,
        keywords: [String]
    ) -> [HeaderLine] {
        let normalizedKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return headers.enumerated().map { index, header in
            let id = headerID(index: index, name: header.0, value: header.1)
            let haystack = "\(header.0)\n\(header.1)".lowercased()
            let keywordMatched = normalizedKeywords.contains { haystack.contains($0) }
            return HeaderLine(
                id: id,
                name: header.0,
                value: header.1,
                isStruck: manuallyStruckIDs.contains(id) || keywordMatched
            )
        }
    }

    static func importantHeaders(from lines: [HeaderLine]) -> [HeaderLine] {
        importantHeaders(from: lines, names: defaultImportantHeaderNames)
    }

    static func importantHeaders(from lines: [HeaderLine], names: [String]) -> [HeaderLine] {
        let normalizedNames = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return normalizedNames.flatMap { wanted in
            lines.filter { $0.name.lowercased() == wanted }
        }
    }

    static func sendableHeaders(from lines: [HeaderLine]) -> [(String, String)] {
        lines
            .filter { !$0.isStruck }
            .map { ($0.name, $0.value) }
    }

    static func headerLine(in rawText: String, atUTF16Location location: Int) -> HeaderLine? {
        let text = rawText as NSString
        guard text.length > 0 else { return nil }
        guard location >= 0, location != NSNotFound else { return nil }

        let clampedLocation = max(0, min(location, max(text.length - 1, 0)))
        var scanLocation = 0
        var headerIndex = 0
        var lineNumber = 0

        while scanLocation < text.length {
            let lineRange = text.lineRange(for: NSRange(location: scanLocation, length: 0))
            let rawLine = text.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            let containsLocation = clampedLocation >= lineRange.location
                && clampedLocation < lineRange.location + lineRange.length

            if lineNumber == 0 {
                scanLocation = lineRange.location + lineRange.length
                lineNumber += 1
                continue
            }

            if line.isEmpty {
                return nil
            }

            defer {
                scanLocation = lineRange.location + lineRange.length
                lineNumber += 1
            }

            guard containsLocation else {
                if line.contains(":") {
                    headerIndex += 1
                }
                continue
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                return nil
            }

            let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }

            return HeaderLine(
                id: headerID(index: headerIndex, name: name, value: value),
                name: name,
                value: value,
                isStruck: false
            )
        }

        return nil
    }

    static func headerName(in rawText: String, selectedUTF16Range selection: NSRange) -> String? {
        let text = rawText as NSString
        guard text.length > 0, selection.length > 0, selection.location != NSNotFound else { return nil }

        var scanLocation = 0
        var lineNumber = 0

        while scanLocation < text.length {
            let lineRange = text.lineRange(for: NSRange(location: scanLocation, length: 0))
            let rawLine = text.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))

            defer {
                scanLocation = lineRange.location + lineRange.length
                lineNumber += 1
            }

            if lineNumber == 0 {
                continue
            }
            if line.isEmpty {
                return nil
            }
            guard let colonIndex = line.firstIndex(of: ":") else {
                continue
            }

            let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let visibleLineLength = (rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")) as NSString).length
            let visibleLineRange = NSRange(location: lineRange.location, length: visibleLineLength)
            if NSIntersectionRange(visibleLineRange, selection).length > 0 {
                return name
            }
        }

        return nil
    }

    static func filteredRequest(
        _ request: HTTPRequest,
        manuallyStruckIDs: Set<HeaderLine.ID>,
        keywords: [String],
        redactMatchingKeywords: Bool
    ) -> HTTPRequest {
        var filtered = request
        let activeKeywords = redactMatchingKeywords ? keywords : []
        let lines = makeHeaderLines(
            from: request.headers,
            manuallyStruckIDs: manuallyStruckIDs,
            keywords: activeKeywords
        )
        filtered.headers = sendableHeaders(from: lines)
        return filtered
    }

    static func headerID(index: Int, name: String, value: String) -> HeaderLine.ID {
        "\(index)|\(name.lowercased())"
    }
}
