import Foundation

struct CodexRunResult: Codable, Hashable {
    var reply: String
    var strikeHeaderNames: [String]
    var strikeQueryParamNames: [String]
    var redactionKeywords: [String]
    var highlights: [RiskHighlight]

    enum CodingKeys: String, CodingKey {
        case reply
        case strikeHeaderNames = "strike_header_names"
        case strikeQueryParamNames = "strike_query_param_names"
        case redactionKeywords = "redaction_keywords"
        case highlights
    }

    init(
        reply: String,
        strikeHeaderNames: [String] = [],
        strikeQueryParamNames: [String] = [],
        redactionKeywords: [String] = [],
        highlights: [RiskHighlight] = []
    ) {
        self.reply = reply
        self.strikeHeaderNames = strikeHeaderNames
        self.strikeQueryParamNames = strikeQueryParamNames
        self.redactionKeywords = redactionKeywords
        self.highlights = highlights
    }
}
