import Foundation

struct TextLineIndex {
    struct Line: Identifiable, Equatable {
        let id: Int
        let lineNumber: Int
        let contentRange: NSRange
        let lineRange: NSRange
        let text: String
    }

    private struct IndexedRange: Equatable {
        let lineRange: NSRange
        let contentRange: NSRange
    }

    private let source: NSString
    private let ranges: [IndexedRange]

    let totalLineCount: Int
    let fullTextLength: Int

    var lineNumbers: Range<Int> {
        guard totalLineCount > 0 else { return 1..<1 }
        return 1..<(totalLineCount + 1)
    }

    init(text: String) {
        let started = Date()
        let source = text as NSString
        let ranges = Self.ranges(in: source)

        self.source = source
        self.ranges = ranges
        self.totalLineCount = ranges.count
        self.fullTextLength = source.length

        PerformanceLogStore.appendIfSlow(
            operation: "line-index",
            source: "response",
            elapsed: Date().timeIntervalSince(started),
            textLength: source.length,
            queryLength: 0,
            matchCount: ranges.count
        )
    }

    func contains(lineNumber: Int) -> Bool {
        lineNumbers.contains(lineNumber)
    }

    func line(at lineNumber: Int) -> Line? {
        guard contains(lineNumber: lineNumber) else { return nil }
        let index = lineNumber - 1
        let range = ranges[index]
        return Line(
            id: lineNumber,
            lineNumber: lineNumber,
            contentRange: range.contentRange,
            lineRange: range.lineRange,
            text: source.substring(with: range.contentRange)
        )
    }

    private static func ranges(in source: NSString) -> [IndexedRange] {
        guard source.length > 0 else { return [] }

        var result: [IndexedRange] = []
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let rawLine = source.substring(with: lineRange)
            let visibleLength = (rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")) as NSString).length
            let contentRange = NSRange(location: lineRange.location, length: min(visibleLength, lineRange.length))
            result.append(IndexedRange(lineRange: lineRange, contentRange: contentRange))

            let nextLocation = lineRange.location + lineRange.length
            guard nextLocation > location else { break }
            location = nextLocation
        }
        return result
    }
}
