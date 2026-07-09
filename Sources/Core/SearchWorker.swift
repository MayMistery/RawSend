import Foundation

enum SearchWorker {
    static func matches(in text: String, query: String, source: String) -> [SearchMatch] {
        let started = Date()
        let matches = SearchEngine.matches(in: text, query: query)
        PerformanceLogStore.appendIfSlow(
            operation: "search",
            source: source,
            elapsed: Date().timeIntervalSince(started),
            textLength: (text as NSString).length,
            queryLength: (query as NSString).length,
            matchCount: matches.count
        )
        return matches
    }
}
