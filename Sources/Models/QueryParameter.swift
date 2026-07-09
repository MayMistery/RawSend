import Foundation

struct QueryParameter: Identifiable, Hashable {
    let id: String
    let name: String
    let value: String?
    let raw: String
    var isStruck: Bool

    var displayText: String {
        if let value {
            return "\(name)=\(value)"
        }
        return name
    }
}
