import Foundation

struct JSONSyntaxToken: Hashable {
    enum Kind: String {
        case key
        case string
        case number
        case literal
        case punctuation
    }

    let kind: Kind
    let range: NSRange
}

struct JSONSyntaxHighlighter {
    static let defaultMaximumTokens = 20_000

    static func tokenRanges(
        in text: String,
        range inputRange: NSRange? = nil,
        maximumTokens: Int = defaultMaximumTokens
    ) -> [JSONSyntaxToken] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let scanRange = inputRange.map { NSIntersectionRange($0, fullRange) } ?? fullRange
        guard scanRange.length > 0 else { return [] }
        guard maximumTokens > 0 else { return [] }
        guard looksLikeJSON(in: source, range: scanRange) else { return [] }

        var tokens: [JSONSyntaxToken] = []
        var location = scanRange.location
        let end = scanRange.location + scanRange.length

        while location < end, tokens.count < maximumTokens {
            let character = source.character(at: location)

            if isWhitespace(character) {
                location += 1
                continue
            }

            if character == quote {
                let stringRange = readString(in: source, from: location, end: end)
                let kind: JSONSyntaxToken.Kind = isKeyString(in: source, after: stringRange.location + stringRange.length, end: end)
                    ? .key
                    : .string
                tokens.append(JSONSyntaxToken(kind: kind, range: stringRange))
                location = stringRange.location + max(stringRange.length, 1)
                continue
            }

            if isNumberStart(character) {
                let numberRange = readNumber(in: source, from: location, end: end)
                tokens.append(JSONSyntaxToken(kind: .number, range: numberRange))
                location = numberRange.location + max(numberRange.length, 1)
                continue
            }

            if let literalRange = readLiteral(in: source, from: location, end: end) {
                tokens.append(JSONSyntaxToken(kind: .literal, range: literalRange))
                location = literalRange.location + literalRange.length
                continue
            }

            if isPunctuation(character) {
                tokens.append(JSONSyntaxToken(kind: .punctuation, range: NSRange(location: location, length: 1)))
            }
            location += 1
        }

        return tokens
    }

    private static let quote = unichar(34)
    private static let backslash = unichar(92)
    private static let colon = unichar(58)

    private static func looksLikeJSON(in source: NSString, range: NSRange) -> Bool {
        var location = range.location
        let end = range.location + range.length
        while location < end {
            let character = source.character(at: location)
            if isWhitespace(character) {
                location += 1
                continue
            }
            return character == unichar(123) || character == unichar(91)
        }
        return false
    }

    private static func readString(in source: NSString, from start: Int, end: Int) -> NSRange {
        var location = start + 1
        var escaped = false

        while location < end {
            let character = source.character(at: location)
            if escaped {
                escaped = false
            } else if character == backslash {
                escaped = true
            } else if character == quote {
                return NSRange(location: start, length: location - start + 1)
            }
            location += 1
        }

        return NSRange(location: start, length: max(1, end - start))
    }

    private static func isKeyString(in source: NSString, after start: Int, end: Int) -> Bool {
        var location = start
        while location < end {
            let character = source.character(at: location)
            if isWhitespace(character) {
                location += 1
                continue
            }
            return character == colon
        }
        return false
    }

    private static func readNumber(in source: NSString, from start: Int, end: Int) -> NSRange {
        var location = start
        while location < end {
            let character = source.character(at: location)
            if isDigit(character)
                || character == unichar(45)
                || character == unichar(43)
                || character == unichar(46)
                || character == unichar(69)
                || character == unichar(101) {
                location += 1
            } else {
                break
            }
        }
        return NSRange(location: start, length: max(1, location - start))
    }

    private static func readLiteral(in source: NSString, from start: Int, end: Int) -> NSRange? {
        for literal in ["true", "false", "null"] {
            let length = (literal as NSString).length
            guard start + length <= end else { continue }
            let range = NSRange(location: start, length: length)
            if source.substring(with: range) == literal {
                return range
            }
        }
        return nil
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == unichar(32) || character == unichar(9) || character == unichar(10) || character == unichar(13)
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= unichar(48) && character <= unichar(57)
    }

    private static func isNumberStart(_ character: unichar) -> Bool {
        isDigit(character) || character == unichar(45)
    }

    private static func isPunctuation(_ character: unichar) -> Bool {
        character == unichar(123)
            || character == unichar(125)
            || character == unichar(91)
            || character == unichar(93)
            || character == colon
            || character == unichar(44)
    }
}
