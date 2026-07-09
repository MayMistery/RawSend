import Foundation

struct HeaderLine: Identifiable, Hashable {
    let id: String
    let name: String
    let value: String
    var isStruck: Bool

    var displayText: String {
        "\(name): \(value)"
    }
}
