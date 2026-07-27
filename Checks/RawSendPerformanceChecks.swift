import Foundation

@main
struct RawSendPerformanceChecks {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        func measure(_ name: String, limit: TimeInterval, _ work: () -> Void) {
            let started = Date()
            work()
            let elapsed = Date().timeIntervalSince(started)
            expect(elapsed < limit, "\(name) took \(String(format: "%.3f", elapsed))s, limit \(limit)s")
        }

        func findMatches(in text: String, query: String, limit: Int = 5_000) -> [SearchMatch] {
            let source = text as NSString
            var matches: [SearchMatch] = []
            var searchRange = NSRange(location: 0, length: source.length)
            while matches.count < limit {
                let found = source.range(of: query, options: [.caseInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                matches.append(SearchMatch(
                    id: "\(found.location)-\(found.length)",
                    range: found,
                    text: source.substring(with: found),
                    lineNumber: lineNumber(forUTF16Location: found.location, in: source),
                    columnNumber: 1
                ))
                let nextLocation = found.location + max(found.length, 1)
                guard nextLocation < source.length else { break }
                searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
            }
            return matches
        }

        func lineNumber(forUTF16Location location: Int, in source: NSString) -> Int {
            var line = 1
            var index = 0
            while index < min(location, source.length) {
                if source.character(at: index) == unichar(10) {
                    line += 1
                }
                index += 1
            }
            return line
        }

        let staleSearchMatch = SearchMatch(
            id: "stale",
            range: NSRange(location: 30, length: 4),
            text: "test",
            lineNumber: 1,
            columnNumber: 31
        )
        let staleSearchPlan = TextHighlightPlan.make(
            previousSearchMatches: [],
            currentSearchMatches: [staleSearchMatch],
            selectedIndex: 0,
            sourceText: "short text"
        )
        expect(staleSearchPlan.searchRangesToApply.isEmpty, "stale search ranges should not be applied after text shrinks")
        expect(
            TextHighlightPlan.validRange(for: staleSearchMatch, in: "short text") == nil,
            "stale search ranges should not be selected after text shrinks"
        )

        let body = (0..<60_000)
            .map { #"{"id":\#($0),"ok":true}"# }
            .joined(separator: "\n")
        let fullText = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n[\n\(body)\n]"
        let response = HTTPResponse(urlResponse: nil, data: Data(fullText.utf8), elapsed: 0.1)

        measure("cached fullResponseText", limit: 0.05) {
            for _ in 0..<20 {
                _ = response.fullResponseText
            }
        }

        measure("archived response restore avoids body copy", limit: 0.05) {
            let restored = HTTPResponse.archived(HistoryResponse(response: response))
            expect(restored.body.isEmpty, "history restore should not duplicate full response text into body data")
            expect(restored.bodyString.isEmpty, "history restore should not duplicate full response text into bodyString")
            expect(restored.fullResponseText == response.fullResponseText, "history restore should keep the archived full response text")
        }

        measure("identical large diff", limit: 0.05) {
            let result = DiffEngine.diff(http: response, https: response, language: .english)
            expect(result.lines.isEmpty, "identical diff should not materialize same lines")
        }

        measure("large response line index builds once", limit: 0.08) {
            let text = "HTTP/1.1 200 OK\r\n\r\n" + String(repeating: #"{"ok":true}"# + "\n", count: 80_000)
            let index = TextLineIndex(text: text)

            expect(index.totalLineCount == 80_002, "line index should cover the full response")
            expect(index.lineNumbers.lowerBound == 1, "line index should start at the first line")
            expect(index.lineNumbers.upperBound == 80_003, "line index should expose every global line id")
        }

        measure("large response line access stays lazy", limit: 0.05) {
            let tailLine = 80_003
            let text = "HTTP/1.1 200 OK\r\n\r\n" + String(repeating: #"{"ok":true}"# + "\n", count: 80_000) + "tail-needle"
            let index = TextLineIndex(text: text)

            expect(index.line(at: 1)?.text == "HTTP/1.1 200 OK", "line index should read the first line on demand")
            expect(index.line(at: tailLine)?.text == "tail-needle", "line index should read a tail line on demand")
        }

        // MARK: - Regression against the latest local history recording

        if let latest = loadLatestHistoryEntry() {
            let text = latest.largest.fullText
            let textLength = (text as NSString).length

            measure("latest local history line index (\(textLength) chars)", limit: 0.08) {
                let index = TextLineIndex(text: text)
                expect(index.totalLineCount > 0, "latest history line index should have content")
                expect(index.line(at: 1) != nil, "latest history first line should be readable")
                expect(index.line(at: index.totalLineCount) != nil, "latest history tail line should be readable")
            }

            if let query = ["token", "status", "id", "\"", "e", " "].first(where: { !findMatches(in: text, query: $0, limit: 1).isEmpty }) {
                let matches = findMatches(in: text, query: query)
                if let lastMatch = matches.last {
                    measure("latest local history search line navigation", limit: 0.08) {
                        let index = TextLineIndex(text: text)
                        expect(index.contains(lineNumber: lastMatch.lineNumber), "index should contain the navigated match line")
                        expect(index.line(at: lastMatch.lineNumber) != nil, "navigated match line should be readable")
                    }
                }
            }

            if let pair = latest.identicalPair {
                measure("latest local history identical diff", limit: 0.05) {
                    let result = DiffEngine.diff(http: pair.http, https: pair.https, language: .english)
                    expect(result.lines.isEmpty, "latest identical diff should not materialize same lines")
                }
            }
        } else {
            print("RawSendPerformanceChecks: no local history with responses found, skipping history regression")
        }

        if failures.isEmpty {
            print("RawSendPerformanceChecks passed")
        } else {
            for failure in failures {
                fputs("FAIL: \(failure)\n", stderr)
            }
            exit(1)
        }
    }

    private struct LatestHistoryEntry {
        let largest: HistoryResponse
        let identicalPair: (http: HTTPResponse, https: HTTPResponse)?
    }

    private static func loadLatestHistoryEntry() -> LatestHistoryEntry? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent("RawSend/history.json")
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return nil
        }

        for item in history {
            let responses = [item.httpResponse, item.httpsResponse].compactMap { $0 }
            guard let largest = responses.max(by: { $0.fullText.utf16.count < $1.fullText.utf16.count }) else { continue }

            var identicalPair: (HTTPResponse, HTTPResponse)?
            if let http = item.httpResponse,
               let https = item.httpsResponse,
               http.fullText == https.fullText {
                identicalPair = (HTTPResponse.archived(http), HTTPResponse.archived(https))
            }
            return LatestHistoryEntry(largest: largest, identicalPair: identicalPair)
        }
        return nil
    }
}
