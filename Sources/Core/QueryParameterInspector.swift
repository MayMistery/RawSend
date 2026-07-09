import Foundation

struct QueryParameterInspector {
    struct ParameterRange {
        let parameter: QueryParameter
        let range: NSRange
    }

    static func makeParameters(
        from path: String,
        manuallyStruckIDs: Set<QueryParameter.ID>,
        keywords: [String]
    ) -> [QueryParameter] {
        guard let parts = split(path: path) else { return [] }
        let normalizedKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return parts.query.split(separator: "&", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, rawPart -> QueryParameter? in
                let raw = String(rawPart)
                guard !raw.isEmpty else { return nil }
                let (name, value) = splitParameter(raw)
                let id = parameterID(index: index, name: name)
                let haystack = "\(name)\n\(value ?? "")\n\(raw)".lowercased()
                let keywordMatched = normalizedKeywords.contains { haystack.contains($0) }
                return QueryParameter(
                    id: id,
                    name: name,
                    value: value,
                    raw: raw,
                    isStruck: manuallyStruckIDs.contains(id) || keywordMatched
                )
            }
    }

    static func filteredRequest(
        _ request: HTTPRequest,
        manuallyStruckIDs: Set<QueryParameter.ID>,
        keywords: [String],
        redactMatchingKeywords: Bool
    ) -> HTTPRequest {
        guard let parts = split(path: request.path) else { return request }
        let activeKeywords = redactMatchingKeywords ? keywords : []
        let parameters = makeParameters(
            from: request.path,
            manuallyStruckIDs: manuallyStruckIDs,
            keywords: activeKeywords
        )
        let kept = parameters.filter { !$0.isStruck }.map(\.raw)

        var filtered = request
        if kept.isEmpty {
            filtered.path = parts.prefix + parts.fragment
        } else {
            filtered.path = "\(parts.prefix)?\(kept.joined(separator: "&"))\(parts.fragment)"
        }
        return filtered
    }

    static func parameter(in rawText: String, atUTF16Location location: Int) -> QueryParameter? {
        parameterRanges(in: rawText, manuallyStruckIDs: [], keywords: [])
            .first { contains(location: location, in: $0.range) }?
            .parameter
    }

    static func parameterName(in rawText: String, selectedUTF16Range selection: NSRange) -> String? {
        guard selection.length > 0, selection.location != NSNotFound else { return nil }
        return parameterRanges(in: rawText, manuallyStruckIDs: [], keywords: [])
            .first { NSIntersectionRange($0.range, selection).length > 0 }?
            .parameter.name
    }

    static func parameterRanges(
        in rawText: String,
        manuallyStruckIDs: Set<QueryParameter.ID>,
        keywords: [String]
    ) -> [ParameterRange] {
        let text = rawText as NSString
        guard text.length > 0 else { return [] }

        let firstLineRange = text.lineRange(for: NSRange(location: 0, length: 0))
        let firstLine = text.substring(with: firstLineRange)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let firstLineNSString = firstLine as NSString
        let tokens = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard tokens.count >= 2 else { return [] }

        let path = String(tokens[1])
        guard let parts = split(path: path),
              let queryStartInPath = path.firstIndex(of: "?") else { return [] }

        let pathRangeInLine = firstLineNSString.range(of: path)
        guard pathRangeInLine.location != NSNotFound else { return [] }

        let queryStartOffset = path.distance(from: path.startIndex, to: path.index(after: queryStartInPath))
        var parameterStartInQuery = 0
        let parameters = makeParameters(
            from: path,
            manuallyStruckIDs: manuallyStruckIDs,
            keywords: keywords
        )
        var ranges: [ParameterRange] = []
        let rawParts = parts.query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)

        for (rawIndex, rawPart) in rawParts.enumerated() {
            defer { parameterStartInQuery += rawPart.count + 1 }
            guard !rawPart.isEmpty,
                  let parameter = parameters.first(where: { $0.id == parameterID(index: rawIndex, name: splitParameter(rawPart).name) }) else {
                continue
            }
            let location = firstLineRange.location + pathRangeInLine.location + queryStartOffset + parameterStartInQuery
            ranges.append((ParameterRange(
                parameter: parameter,
                range: NSRange(location: location, length: (rawPart as NSString).length)
            )))
        }

        return ranges
    }

    static func parameterID(index: Int, name: String) -> QueryParameter.ID {
        "query|\(index)|\(name.lowercased())"
    }

    private static func split(path: String) -> (prefix: String, query: String, fragment: String)? {
        guard let question = path.firstIndex(of: "?") else { return nil }
        let prefix = String(path[..<question])
        let afterQuestion = path.index(after: question)
        let rest = String(path[afterQuestion...])

        if let hash = rest.firstIndex(of: "#") {
            return (
                prefix,
                String(rest[..<hash]),
                String(rest[hash...])
            )
        }

        return (prefix, rest, "")
    }

    private static func splitParameter(_ raw: String) -> (name: String, value: String?) {
        guard let equals = raw.firstIndex(of: "=") else {
            return (decode(raw), nil)
        }
        let name = String(raw[..<equals])
        let value = String(raw[raw.index(after: equals)...])
        return (decode(name), decode(value))
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    private static func contains(location: Int, in range: NSRange) -> Bool {
        location >= range.location && location < range.location + range.length
    }
}
