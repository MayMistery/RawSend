import Foundation

struct TextLineRanges {
    static func range(forLineNumber lineNumber: Int, in text: String) -> NSRange? {
        guard lineNumber > 0 else { return nil }
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        var currentLine = 1
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            if currentLine == lineNumber {
                let rawLine = nsText.substring(with: lineRange)
                let visibleLength = (rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")) as NSString).length
                return NSRange(location: lineRange.location, length: max(visibleLength, lineRange.length))
            }

            let nextLocation = lineRange.location + lineRange.length
            guard nextLocation > location else { break }
            location = nextLocation
            currentLine += 1
        }

        return nil
    }
}
