import SwiftUI

struct CodexChatView: View {
    @EnvironmentObject var appState: AppState

    private var struckHeaders: [HeaderLine] {
        appState.requestHeaderLines.filter(\.isStruck)
    }

    private var struckQueryParameters: [QueryParameter] {
        appState.requestQueryParameters.filter(\.isStruck)
    }

    private var hasResponse: Bool {
        appState.httpResponse != nil || appState.httpsResponse != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            CodexConsoleHeader(
                host: appState.parsedHost,
                hasResponse: hasResponse,
                isRunning: appState.isCodexRunning,
                highlightCount: appState.riskHighlights.count
            )

            Divider()

            HSplitView {
                CodexTranscriptPane(
                    messages: appState.codexMessages,
                    isRunning: appState.isCodexRunning
                )
                .frame(minWidth: 470)

                CodexActionSummaryPanel(
                    struckHeaders: struckHeaders,
                    struckQueryParameters: struckQueryParameters,
                    redactionKeywords: appState.preferences.redactionKeywords,
                    riskHighlights: appState.riskHighlights,
                    clearHighlights: { appState.clearRiskHighlights() }
                )
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            }

            Divider()

            CodexCommandBar(
                draft: $appState.codexDraft,
                errorMessage: appState.codexErrorMessage,
                isRunning: appState.isCodexRunning,
                send: { appState.runCodexChat() }
            )
        }
        .frame(width: 900, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CodexConsoleHeader: View {
    @EnvironmentObject var appState: AppState
    let host: String
    let hasResponse: Bool
    let isRunning: Bool
    let highlightCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.t(.codexConsole))
                    .font(.system(size: 15, weight: .semibold))
                Text(host.isEmpty ? appState.t(.hostMissing) : host)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 8) {
                CodexStatusPill(
                    title: appState.t(.request),
                    value: host.isEmpty ? appState.t(.requestInvalid) : appState.t(.requestReady),
                    state: host.isEmpty ? .warning : .ok
                )
                CodexStatusPill(
                    title: appState.t(.response),
                    value: hasResponse ? appState.t(.responseLoaded) : appState.t(.responseEmpty),
                    state: hasResponse ? .ok : .neutral
                )
                CodexStatusPill(
                    title: appState.t(.riskHighlights),
                    value: "\(highlightCount)",
                    state: highlightCount > 0 ? .warning : .neutral
                )
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct CodexTranscriptPane: View {
    @EnvironmentObject var appState: AppState
    let messages: [CodexChatMessage]
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appState.t(.conversation))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(messages.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if messages.isEmpty {
                        CodexEmptyTranscriptView()
                    }

                    ForEach(messages) { message in
                        CodexTranscriptRow(message: message)
                    }

                    if isRunning {
                        CodexRunningRow()
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct CodexActionSummaryPanel: View {
    @EnvironmentObject var appState: AppState
    let struckHeaders: [HeaderLine]
    let struckQueryParameters: [QueryParameter]
    let redactionKeywords: [String]
    let riskHighlights: [RiskHighlight]
    let clearHighlights: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appState.t(.actionStatus))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: clearHighlights) {
                    Image(systemName: "eraser")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(riskHighlights.isEmpty)
                .help(appState.t(.clearHighlights))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        CodexMetricTile(title: appState.t(.struckHeadersMetric), value: "\(struckHeaders.count)", icon: "rectangle.3.group")
                        CodexMetricTile(title: appState.t(.queryParameters), value: "\(struckQueryParameters.count)", icon: "link")
                        CodexMetricTile(title: appState.t(.riskLines), value: "\(riskHighlights.count)", icon: "line.3.horizontal.decrease.circle")
                    }

                    CodexActionSection(title: appState.t(.headersStruck), icon: "minus.circle") {
                        if struckHeaders.isEmpty {
                            CodexEmptyLine()
                        } else {
                            ForEach(struckHeaders) { header in
                                CodexNameRow(name: header.name, subtitle: "Header")
                            }
                        }
                    }

                    CodexActionSection(title: appState.t(.struckQueryParameters), icon: "slash.circle") {
                        if struckQueryParameters.isEmpty {
                            CodexEmptyLine()
                        } else {
                            ForEach(struckQueryParameters) { parameter in
                                CodexNameRow(name: parameter.name, subtitle: "Query")
                            }
                        }
                    }

                    CodexActionSection(title: appState.t(.filterKeywords), icon: "tag") {
                        if redactionKeywords.isEmpty {
                            CodexEmptyLine()
                        } else {
                            FlowLayout(items: Array(redactionKeywords.prefix(16))) { keyword in
                                Text(keyword)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }

                    CodexActionSection(title: appState.t(.riskHighlights), icon: "scope") {
                        if riskHighlights.isEmpty {
                            CodexEmptyLine()
                        } else {
                            ForEach(riskHighlights.prefix(8)) { highlight in
                                CodexHighlightRow(highlight: highlight)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct CodexCommandBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var draft: String
    let errorMessage: String?
    let isRunning: Bool
    let send: () -> Void

    private var canSend: Bool {
        !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)

                if draft.isEmpty {
                    Text(appState.t(.codexCommandPlaceholder))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 86)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
            )

            HStack(spacing: 10) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if isRunning {
                    Text(appState.t(.codexRunning))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(appState.t(.ready))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: send) {
                    Label(appState.t(.send), systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }
}

private struct CodexTranscriptRow: View {
    let message: CodexChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(roleColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(roleTitle)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(roleColor)
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(message.role == .system ? Color.red.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 27)
        }
    }

    private var roleTitle: String {
        switch message.role {
        case .user: return "USER"
        case .assistant: return "CODEX"
        case .system: return "SYSTEM"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .green
        case .system: return .red
        }
    }
}

private struct CodexRunningRow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(appState.t(.codexAnalyzing))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CodexEmptyTranscriptView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text(appState.t(.codexFirstInstruction))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }
}

private struct CodexActionSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct CodexMetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct CodexNameRow: View {
    let name: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 7) {
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct CodexHighlightRow: View {
    let highlight: RiskHighlight

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(highlight.source.rawValue):\(highlight.line)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(severityColor)
                .frame(width: 74, alignment: .leading)
            Text(highlight.reason)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(severityColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var severityColor: Color {
        switch highlight.severity.lowercased() {
        case "high": return .red
        case "low": return .blue
        default: return .orange
        }
    }
}

private struct CodexEmptyLine: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text(appState.t(.none))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.vertical, 2)
    }
}

private struct CodexStatusPill: View {
    enum State {
        case ok
        case warning
        case neutral
    }

    let title: String
    let value: String
    let state: State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var color: Color {
        switch state {
        case .ok: return .green
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    init(items: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chunkedItems, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    private var chunkedItems: [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var currentLength = 0

        for item in items {
            let projectedLength = currentLength + item.count + 2
            if projectedLength > 28, !current.isEmpty {
                rows.append(current)
                current = [item]
                currentLength = item.count
            } else {
                current.append(item)
                currentLength = projectedLength
            }
        }

        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
