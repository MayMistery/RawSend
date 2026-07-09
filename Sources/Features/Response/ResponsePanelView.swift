import SwiftUI
import AppKit

/// 响应面板：HTTP / HTTPS / Diff 三个 Tab
struct ResponsePanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Tab 栏
            HStack(spacing: 0) {
                ForEach(AppState.ResponseTab.allCases, id: \.self) { tab in
                    ResponseTabButton(tab: tab, isSelected: appState.selectedResponseTab == tab) {
                        appState.selectedResponseTab = tab
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()

            // 内容
            Group {
                switch appState.selectedResponseTab {
                case .http:
                    SingleResponseView(response: appState.httpResponse, label: "HTTP")
                case .https:
                    SingleResponseView(response: appState.httpsResponse, label: "HTTPS")
                case .diff:
                    DiffResponseView(
                        http: appState.httpResponse,
                        https: appState.httpsResponse,
                        language: appState.appLanguage
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Tab 按钮

struct ResponseTabButton: View {
    let tab: AppState.ResponseTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单响应视图

struct SingleResponseView: View {
    @EnvironmentObject var appState: AppState
    let response: HTTPResponse?
    let label: String
    @State private var displayMode: ResponseDisplayMode = .raw

    var body: some View {
        if let response = response {
            let responseText = response.fullResponseText
            let previewHTML = HTTPTextSyntax.htmlPreviewBody(in: responseText)
            let activeDisplayMode: ResponseDisplayMode = previewHTML == nil ? .raw : displayMode
            let matches = appState.responseSearchMatches
            let selectedMatch = appState.selectedResponseSearchIndex.flatMap { index in
                matches.indices.contains(index) ? matches[index] : nil
            }

            VStack(spacing: 0) {
                // 状态栏
                HStack(spacing: 12) {
                    StatusBadge(code: response.statusCode)
                    if let debugInfo = response.debugInfo {
                        Button(action: { copyDebugInfo(debugInfo) }) {
                            Label(appState.t(.copyErrorInfo), systemImage: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .help(appState.t(.copyErrorInfo))

                        Button(action: { openLogFile(debugInfo) }) {
                            Label(appState.t(.openLogFile), systemImage: "doc.text.magnifyingglass")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .help(debugInfo.localLogPath)
                    }
                    if response.isRedirect {
                        Button(action: { appState.sendRequest(followRedirectsOverride: true) }) {
                            Label(appState.t(.follow), systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isSending)
                        .help(response.locationHeader.map { appState.tf(.followLocation, $0) } ?? appState.t(.followRedirects))
                    }
                    Text(String(format: "%.0fms", response.elapsed * 1000))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSize(response.size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                HStack {
                    if previewHTML != nil {
                        Picker("", selection: $displayMode) {
                            Text(appState.t(.responseRaw)).tag(ResponseDisplayMode.raw)
                            Text(appState.t(.responsePreview)).tag(ResponseDisplayMode.preview)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }

                    if activeDisplayMode == .raw {
                        SearchToolbarView(
                            query: $appState.responseSearchText,
                            selectedIndex: $appState.selectedResponseSearchIndex,
                            matchCount: matches.count,
                            selectedMatch: selectedMatch,
                            placeholder: appState.t(.responseSearchPlaceholder),
                            focusToken: appState.responseSearchFocusToken,
                            previousAction: { appState.selectPreviousResponseSearchMatch(matchCount: appState.responseSearchMatches.count) },
                            nextAction: { appState.selectNextResponseSearchMatch(matchCount: appState.responseSearchMatches.count) }
                        )
                        .frame(width: 340)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                if activeDisplayMode == .preview, let previewHTML {
                    ResponseHTMLPreviewView(html: previewHTML)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ResponseTextView(
                        text: responseText,
                        lineIndex: response.lineIndex,
                        searchText: appState.responseSearchText,
                        searchMatches: matches,
                        selectedSearchMatchIndex: appState.selectedResponseSearchIndex,
                        riskHighlights: appState.riskHighlights.filter { $0.source == .response },
                        markActive: { appState.activateResponseSearchScope() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .onAppear {
                if previewHTML == nil {
                    displayMode = .raw
                }
                appState.updateResponseSearchMatches(in: responseText, resetSelection: true)
            }
            .onChange(of: appState.responseSearchText) { _, _ in
                appState.updateResponseSearchMatches(in: responseText, resetSelection: true)
            }
            .onChange(of: response.id) { _, _ in
                if previewHTML == nil {
                    displayMode = .raw
                }
                appState.updateResponseSearchMatches(in: responseText, resetSelection: true)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.dotted")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(appState.tf(.responseWillAppear, label))
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        return String(format: "%.1fMB", Double(bytes) / 1024 / 1024)
    }

    private func copyDebugInfo(_ debugInfo: ResponseDebugInfo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugInfo.copyText, forType: .string)
    }

    private func openLogFile(_ debugInfo: ResponseDebugInfo) {
        let url = URL(fileURLWithPath: debugInfo.localLogPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private enum ResponseDisplayMode: Hashable {
    case raw
    case preview
}

// MARK: - 状态码徽标

struct StatusBadge: View {
    let code: Int

    var body: some View {
        Text("\(code)")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }
}

// MARK: - Diff 视图

struct DiffResponseView: View {
    let http: HTTPResponse?
    let https: HTTPResponse?
    let language: AppLanguage

    var body: some View {
        let diffResult = DiffEngine.diff(http: http, https: https, language: language)

        VStack(spacing: 0) {
            // 摘要
            HStack {
                Image(systemName: diffResult.lines.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundColor(diffResult.lines.isEmpty ? .green : .orange)
                Text(diffResult.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if diffResult.lines.isEmpty && http == nil && https == nil {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(Localizer.text(.diffNeedsBothResponses, language: language))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffResult.lines) { line in
                            Text(line.content)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                                .background(lineBackground(line.type))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func lineBackground(_ type: DiffEngine.DiffLine.LineType) -> Color {
        switch type {
        case .same: return .clear
        case .added: return .green.opacity(0.15)
        case .removed: return .red.opacity(0.15)
        case .modified: return .yellow.opacity(0.15)
        }
    }
}
