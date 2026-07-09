import Foundation
import FindFaster

struct SearchEngine {
    static let defaultMaximumMatches = 5_000

    static func matches(in text: String, query: String, maximumMatches: Int = defaultMaximumMatches) -> [SearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard maximumMatches > 0 else { return [] }

        let source = text as NSString
        let lineStarts = lineStartLocations(in: source)
        let normalizedText = Array(text.lowercased().utf16)
        let normalizedQuery = Array(trimmedQuery.lowercased().utf16)
        guard !normalizedText.isEmpty, normalizedQuery.count <= normalizedText.count else { return [] }

        var matches: [SearchMatch] = []
        normalizedText.fastSearch(for: normalizedQuery) { location in
            guard matches.count < maximumMatches else { return }
            let range = NSRange(location: location, length: normalizedQuery.count)
            guard NSMaxRange(range) <= source.length else { return }
            let position = linePosition(forUTF16Location: range.location, lineStarts: lineStarts)
            matches.append(SearchMatch(
                id: "\(range.location)-\(range.length)-\(trimmedQuery.lowercased())",
                range: range,
                text: source.substring(with: range),
                lineNumber: position.line,
                columnNumber: position.column
            ))
        }

        return matches
    }

    static func nextIndex(after currentIndex: Int?, matchCount: Int) -> Int? {
        guard matchCount > 0 else { return nil }
        guard let currentIndex else { return 0 }
        return (currentIndex + 1) % matchCount
    }

    static func previousIndex(before currentIndex: Int?, matchCount: Int) -> Int? {
        guard matchCount > 0 else { return nil }
        guard let currentIndex else { return matchCount - 1 }
        return (currentIndex - 1 + matchCount) % matchCount
    }

    private static func lineStartLocations(in source: NSString) -> [Int] {
        var starts = [0]
        var location = 0

        while location < source.length {
            let character = source.character(at: location)
            if character == unichar(10) {
                starts.append(location + 1)
            } else if character == unichar(13) {
                let nextLocation = location + 1
                if nextLocation >= source.length || source.character(at: nextLocation) != unichar(10) {
                    starts.append(nextLocation)
                }
            }
            location += 1
        }

        return starts
    }

    private static func linePosition(forUTF16Location location: Int, lineStarts: [Int]) -> (line: Int, column: Int) {
        var low = 0
        var high = lineStarts.count - 1

        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let lineIndex = max(0, high)
        return (lineIndex + 1, max(1, location - lineStarts[lineIndex] + 1))
    }
}
