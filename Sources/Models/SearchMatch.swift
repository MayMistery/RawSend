import Foundation

struct SearchMatch: Identifiable, Hashable {
    let id: String
    let range: NSRange
    let text: String
    let lineNumber: Int
    let columnNumber: Int
}
