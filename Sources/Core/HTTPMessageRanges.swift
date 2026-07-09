import Foundation

struct HTTPMessageRanges {
    static func bodyRange(in text: String) -> NSRange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }

        let crlfRange = source.range(of: "\r\n\r\n")
        if crlfRange.location != NSNotFound {
            let location = crlfRange.location + crlfRange.length
            return NSRange(location: location, length: source.length - location)
        }

        let lfRange = source.range(of: "\n\n")
        if lfRange.location != NSNotFound {
            let location = lfRange.location + lfRange.length
            return NSRange(location: location, length: source.length - location)
        }

        return nil
    }
}
