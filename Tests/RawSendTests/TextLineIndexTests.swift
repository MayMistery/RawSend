import Foundation
import Testing
@testable import RawSend

@Suite("Text line index")
struct TextLineIndexTests {
    @Test func indexesEveryLineWithoutWindowing() {
        let text = (1...20_000)
            .map { "line-\($0)" }
            .joined(separator: "\n")

        let index = TextLineIndex(text: text)

        #expect(index.totalLineCount == 20_000)
        #expect(index.lineNumbers.lowerBound == 1)
        #expect(index.lineNumbers.upperBound == 20_001)
        #expect(index.line(at: 1)?.text == "line-1")
        #expect(index.line(at: 20_000)?.text == "line-20000")
    }

    @Test func exposesSearchMatchLineRangesAcrossTheFullResponse() {
        let text = "HTTP/1.1 200 OK\r\n" +
            (1...10_000).map { #"{"id":\#($0)}"# }.joined(separator: "\r\n")
        let match = SearchEngine.matches(in: text, query: #""id":9999"#).first

        let index = TextLineIndex(text: text)
        let line = match.flatMap { index.line(at: $0.lineNumber) }

        #expect(match?.lineNumber == 10_000)
        #expect(line?.text == #"{"id":9999}"#)
        #expect(line.map { NSIntersectionRange(match!.range, $0.contentRange).length } == 9)
    }
}
