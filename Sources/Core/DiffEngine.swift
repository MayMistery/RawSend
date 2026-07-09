import SwiftUI

/// Diff 工具：对比两个响应
struct DiffEngine {
    static let maximumDisplayedLines = 5_000

    struct DiffLine: Identifiable {
        let id = UUID()
        let type: LineType
        let content: String

        enum LineType {
            case same
            case added    // 只在 HTTPS
            case removed  // 只在 HTTP
            case modified // 两边都有但不同
        }
    }

    struct DiffResult {
        let lines: [DiffLine]
        let summary: String
    }

    /// 对比两个响应文本
    static func diff(http: HTTPResponse?, https: HTTPResponse?, language: AppLanguage = .english) -> DiffResult {
        let started = Date()
        defer {
            PerformanceLogStore.appendIfSlow(
                operation: "diff",
                source: "response",
                elapsed: Date().timeIntervalSince(started),
                textLength: (http?.fullResponseText.count ?? 0) + (https?.fullResponseText.count ?? 0),
                queryLength: 0,
                matchCount: 0
            )
        }

        guard let http = http, let https = https else {
            return DiffResult(lines: [], summary: Localizer.text(.diffNeedsBothResponses, language: language))
        }

        if http.error != nil || https.error != nil {
            return DiffResult(lines: [], summary: Localizer.text(.diffHasRequestError, language: language))
        }

        let httpText = http.fullResponseText
        let httpsText = https.fullResponseText
        if httpText == httpsText {
            return DiffResult(lines: [], summary: Localizer.text(.diffResponsesIdentical, language: language))
        }

        let httpLines = httpText.components(separatedBy: "\n")
        let httpsLines = httpsText.components(separatedBy: "\n")

        var diffLines: [DiffLine] = []
        var diffCount = 0
        let maxLines = max(httpLines.count, httpsLines.count)

        for i in 0..<maxLines {
            let httpLine = i < httpLines.count ? httpLines[i] : ""
            let httpsLine = i < httpsLines.count ? httpsLines[i] : ""

            if httpLine == httpsLine {
                appendLine(DiffLine(type: .same, content: httpLine), to: &diffLines)
            } else {
                diffCount += 1
                if httpLine.isEmpty {
                    appendLine(DiffLine(type: .added, content: "+ \(httpsLine)"), to: &diffLines)
                } else if httpsLine.isEmpty {
                    appendLine(DiffLine(type: .removed, content: "- \(httpLine)"), to: &diffLines)
                } else {
                    appendLine(DiffLine(type: .removed, content: "- \(httpLine)"), to: &diffLines)
                    appendLine(DiffLine(type: .added, content: "+ \(httpsLine)"), to: &diffLines)
                }
            }
        }

        let statusSame = http.statusCode == https.statusCode
        let summary: String
        if diffCount == 0 {
            summary = Localizer.text(.diffResponsesIdentical, language: language)
        } else {
            let status = Localizer.text(statusSame ? .diffStatusSame : .diffStatusDifferent, language: language)
            summary = Localizer.format(.diffDifferences, language: language, status, diffCount)
        }

        return DiffResult(lines: diffLines, summary: summary)
    }

    private static func appendLine(_ line: DiffLine, to lines: inout [DiffLine]) {
        guard lines.count < maximumDisplayedLines else { return }
        lines.append(line)
    }
}
