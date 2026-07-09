import Foundation

struct HTMLSyntaxToken: Hashable {
    enum Kind: String {
        case tag
        case attributeName
        case attributeValue
        case comment
        case entity
        case punctuation
    }

    let kind: Kind
    let range: NSRange
}

struct HTMLSyntaxHighlighter {
    static let defaultMaximumTokens = 20_000

    static func tokenRanges(
        in text: String,
        range inputRange: NSRange? = nil,
        maximumTokens: Int = defaultMaximumTokens
    ) -> [HTMLSyntaxToken] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let scanRange = inputRange.map { NSIntersectionRange($0, fullRange) } ?? fullRange
        guard scanRange.length > 0 else { return [] }
        guard maximumTokens > 0 else { return [] }
        guard looksLikeHTML(in: source, range: scanRange) else { return [] }

        var tokens: [HTMLSyntaxToken] = []
        var location = scanRange.location
        let end = scanRange.location + scanRange.length

        func append(_ kind: HTMLSyntaxToken.Kind, _ range: NSRange) {
            guard tokens.count < maximumTokens,
                  range.location != NSNotFound,
                  range.length > 0,
                  NSIntersectionRange(range, scanRange).length == range.length else { return }
            tokens.append(HTMLSyntaxToken(kind: kind, range: range))
        }

        while location < end, tokens.count < maximumTokens {
            let character = source.character(at: location)
            if character == lessThan {
                if hasPrefix("<!--", in: source, at: location, end: end) {
                    let commentRange = readUntil("-->", in: source, from: location, end: end)
                    append(.comment, commentRange)
                    location = commentRange.location + commentRange.length
                    continue
                }
                location = readTag(in: source, from: location, end: end, append: append)
                continue
            }
            if character == ampersand {
                let entityRange = readEntity(in: source, from: location, end: end)
                if entityRange.length > 1 {
                    append(.entity, entityRange)
                    location = entityRange.location + entityRange.length
                    continue
                }
            }
            location += 1
        }

        return tokens
    }

    private static let lessThan = unichar(60)
    private static let greaterThan = unichar(62)
    private static let slash = unichar(47)
    private static let exclamation = unichar(33)
    private static let question = unichar(63)
    private static let equals = unichar(61)
    private static let singleQuote = unichar(39)
    private static let doubleQuote = unichar(34)
    private static let ampersand = unichar(38)
    private static let semicolon = unichar(59)

    private static func looksLikeHTML(in source: NSString, range: NSRange) -> Bool {
        var location = range.location
        let end = range.location + range.length
        while location < end {
            let character = source.character(at: location)
            if isWhitespace(character) {
                location += 1
                continue
            }
            return character == lessThan
        }
        return false
    }

    private static func readTag(
        in source: NSString,
        from start: Int,
        end: Int,
        append: (HTMLSyntaxToken.Kind, NSRange) -> Void
    ) -> Int {
        append(.punctuation, NSRange(location: start, length: 1))
        var location = start + 1

        while location < end {
            let character = source.character(at: location)
            if character == slash || character == exclamation || character == question {
                append(.punctuation, NSRange(location: location, length: 1))
                location += 1
            } else {
                break
            }
        }

        while location < end, isWhitespace(source.character(at: location)) {
            location += 1
        }

        let tagStart = location
        while location < end, isNameCharacter(source.character(at: location)) {
            location += 1
        }
        if location > tagStart {
            append(.tag, NSRange(location: tagStart, length: location - tagStart))
        }

        while location < end {
            let character = source.character(at: location)
            if character == greaterThan {
                append(.punctuation, NSRange(location: location, length: 1))
                return location + 1
            }
            if character == slash || character == question {
                append(.punctuation, NSRange(location: location, length: 1))
                location += 1
                continue
            }
            if isWhitespace(character) {
                location += 1
                continue
            }

            let nameStart = location
            while location < end, isNameCharacter(source.character(at: location)) {
                location += 1
            }
            if location > nameStart {
                append(.attributeName, NSRange(location: nameStart, length: location - nameStart))
            } else {
                location += 1
                continue
            }

            while location < end, isWhitespace(source.character(at: location)) {
                location += 1
            }
            guard location < end, source.character(at: location) == equals else {
                continue
            }
            append(.punctuation, NSRange(location: location, length: 1))
            location += 1
            while location < end, isWhitespace(source.character(at: location)) {
                location += 1
            }
            guard location < end else { break }

            let valueStart = location
            let valueQuote = source.character(at: location)
            if valueQuote == doubleQuote || valueQuote == singleQuote {
                location += 1
                while location < end, source.character(at: location) != valueQuote {
                    location += 1
                }
                if location < end {
                    location += 1
                }
                append(.attributeValue, NSRange(location: valueStart, length: location - valueStart))
            } else {
                while location < end {
                    let valueCharacter = source.character(at: location)
                    if isWhitespace(valueCharacter) || valueCharacter == greaterThan {
                        break
                    }
                    location += 1
                }
                append(.attributeValue, NSRange(location: valueStart, length: location - valueStart))
            }
        }

        return max(start + 1, location)
    }

    private static func readEntity(in source: NSString, from start: Int, end: Int) -> NSRange {
        var location = start + 1
        while location < end {
            let character = source.character(at: location)
            if character == semicolon {
                return NSRange(location: start, length: location - start + 1)
            }
            if isWhitespace(character) || character == lessThan || character == greaterThan {
                break
            }
            location += 1
        }
        return NSRange(location: start, length: 1)
    }

    private static func readUntil(_ needle: String, in source: NSString, from start: Int, end: Int) -> NSRange {
        let searchRange = NSRange(location: start, length: end - start)
        let found = source.range(of: needle, options: [], range: searchRange)
        if found.location == NSNotFound {
            return searchRange
        }
        return NSRange(location: start, length: found.location - start + found.length)
    }

    private static func hasPrefix(_ prefix: String, in source: NSString, at location: Int, end: Int) -> Bool {
        let length = (prefix as NSString).length
        guard location + length <= end else { return false }
        return source.substring(with: NSRange(location: location, length: length)) == prefix
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == unichar(32) || character == unichar(9) || character == unichar(10) || character == unichar(13)
    }

    private static func isNameCharacter(_ character: unichar) -> Bool {
        (character >= unichar(48) && character <= unichar(57))
            || (character >= unichar(65) && character <= unichar(90))
            || (character >= unichar(97) && character <= unichar(122))
            || character == unichar(45)
            || character == unichar(58)
            || character == unichar(95)
    }
}
