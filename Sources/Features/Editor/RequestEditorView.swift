import SwiftUI
import AppKit

/// Raw HTTP 请求编辑器（基于 NSTextView）
struct RequestEditorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(appState.t(.request))
                    .font(.headline)
                SearchToolbarView(
                    query: $appState.requestSearchText,
                    selectedIndex: $appState.selectedRequestSearchIndex,
                    matchCount: appState.requestSearchMatches.count,
                    selectedMatch: selectedSearchMatch,
                    placeholder: appState.t(.requestSearchPlaceholder),
                    focusToken: appState.requestSearchFocusToken,
                    previousAction: { appState.selectPreviousRequestSearchMatch() },
                    nextAction: { appState.selectNextRequestSearchMatch() }
                )
                .frame(width: 330)
                Spacer()
                Button(action: { appState.rawText = "" }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(appState.t(.clearRequest))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            RequestHeaderSummaryView()

            Divider()

            // 编辑器
            RawTextEditor(
                text: $appState.rawText,
                searchText: appState.requestSearchText,
                searchMatches: appState.requestSearchMatches,
                selectedSearchMatchIndex: appState.selectedRequestSearchIndex,
                manuallyStruckHeaderIDs: appState.manuallyStruckHeaderIDs,
                manuallyStruckQueryParameterIDs: appState.manuallyStruckQueryParameterIDs,
                redactionKeywords: appState.preferences.redactionKeywords,
                redactMatchingHeaders: appState.preferences.redactMatchingHeaders,
                language: appState.appLanguage,
                riskHighlights: appState.riskHighlights.filter { $0.source == .request },
                toggleHeaderStrike: { appState.toggleHeaderStrike($0) },
                toggleQueryParameterStrike: { appState.toggleQueryParameterStrike($0) },
                addRedactionKeyword: { appState.addRedactionKeyword($0) },
                addImportantHeaderName: { appState.addImportantHeaderName($0) },
                markActive: { appState.activateRequestSearchScope() }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.requestSearchText) { _, _ in
            appState.updateRequestSearchMatches(resetSelection: true)
        }
    }

    private var selectedSearchMatch: SearchMatch? {
        guard let index = appState.selectedRequestSearchIndex,
              appState.requestSearchMatches.indices.contains(index) else { return nil }
        return appState.requestSearchMatches[index]
    }
}

private struct RequestHeaderSummaryView: View {
    @EnvironmentObject var appState: AppState
    @State private var newKeyword = ""

    var body: some View {
        VStack(spacing: 0) {
            HeaderSummaryView(title: appState.t(.requestImportantHeaders), headers: appState.importantRequestHeaders)

            HStack(spacing: 8) {
                Toggle(appState.t(.filterSensitiveHeaders), isOn: $appState.preferences.redactMatchingHeaders)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .help(appState.t(.filterSensitiveHeadersHelp))

                TextField(appState.t(.filterKeywords), text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 110)
                    .onSubmit(addKeyword)

                Button(action: addKeyword) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(appState.t(.addFilterKeywordHelp))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addKeyword() {
        appState.addRedactionKeyword(newKeyword)
        newKeyword = ""
    }
}

/// NSTextView 封装，支持语法高亮和自动补全
struct RawTextEditor: NSViewRepresentable {
    @Binding var text: String
    var searchText: String = ""
    var searchMatches: [SearchMatch] = []
    var selectedSearchMatchIndex: Int?
    var manuallyStruckHeaderIDs: Set<HeaderLine.ID> = []
    var manuallyStruckQueryParameterIDs: Set<QueryParameter.ID> = []
    var redactionKeywords: [String] = []
    var redactMatchingHeaders: Bool = true
    var language: AppLanguage = .english
    var riskHighlights: [RiskHighlight] = []
    var toggleHeaderStrike: (HeaderLine) -> Void = { _ in }
    var toggleQueryParameterStrike: (QueryParameter) -> Void = { _ in }
    var addRedactionKeyword: (String) -> Void = { _ in }
    var addImportantHeaderName: (String) -> Void = { _ in }
    var markActive: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            context.coordinator.applyHighlighting()
        } else {
            context.coordinator.applyHighlighting()
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RawTextEditor
        weak var textView: NSTextView?
        private var cachedJSONText: String = ""
        private var cachedJSONBodyRange: NSRange?
        private var cachedJSONTokens: [JSONSyntaxToken] = []
        private var contextHeader: HeaderLine?
        private var contextQueryParameter: QueryParameter?
        private var contextKeyword: String?
        private var contextImportantHeaderName: String?

        // 常见 HTTP 头部补全列表
        static let commonHeaders = [
            "Accept", "Accept-Charset", "Accept-Encoding", "Accept-Language",
            "Authorization", "Cache-Control", "Connection", "Content-Disposition",
            "Content-Encoding", "Content-Length", "Content-Type", "Cookie",
            "Host", "If-Match", "If-Modified-Since", "If-None-Match",
            "Origin", "Pragma", "Referer", "Transfer-Encoding",
            "User-Agent", "X-Forwarded-For", "X-Forwarded-Host",
            "X-Forwarded-Proto", "X-Real-IP", "X-Request-ID",
            "X-Requested-With", "X-CSRF-Token",
        ]

        init(_ parent: RawTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting()
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.markActive()
        }

        func textView(_ textView: NSTextView, completions words: [String],
                      forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard charRange.length > 0 else { return [] }
            let partial = (textView.string as NSString).substring(with: charRange)

            // 检查是否在行首（可能是 header name）
            let lineStart = (textView.string as NSString).lineRange(for: NSRange(location: charRange.location, length: 0)).location
            let beforeCursor = (textView.string as NSString).substring(with: NSRange(location: lineStart, length: charRange.location - lineStart))

            if !beforeCursor.contains(":") {
                // 在 : 之前，补全 header name
                return Self.commonHeaders.filter {
                    $0.lowercased().hasPrefix(partial.lowercased())
                }
            }
            return []
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            parent.markActive()
            contextHeader = HeaderInspector.headerLine(in: view.string, atUTF16Location: charIndex)
            contextQueryParameter = QueryParameterInspector.parameter(in: view.string, atUTF16Location: charIndex)
            contextKeyword = nil
            contextImportantHeaderName = nil

            let menu = menu.copy() as? NSMenu ?? NSMenu()
            if let parameter = contextQueryParameter {
                menu.insertItem(.separator(), at: 0)
                let title = parent.manuallyStruckQueryParameterIDs.contains(parameter.id)
                    ? Localizer.text(.restoreCurrentQueryParameter, language: parent.language)
                    : Localizer.text(.strikeCurrentQueryParameter, language: parent.language)
                let toggleItem = NSMenuItem(title: title, action: #selector(toggleContextQueryParameterStrike), keyEquivalent: "")
                toggleItem.target = self
                menu.insertItem(toggleItem, at: 0)

                let addNameItem = NSMenuItem(title: Localizer.text(.addQueryParameterNameAsKeyword, language: parent.language), action: #selector(addQueryParameterNameAsKeyword), keyEquivalent: "")
                addNameItem.target = self
                menu.insertItem(addNameItem, at: 1)

                if let value = parameter.value, !value.isEmpty {
                    let addValueItem = NSMenuItem(title: Localizer.text(.addQueryParameterValueAsKeyword, language: parent.language), action: #selector(addQueryParameterValueAsKeyword), keyEquivalent: "")
                    addValueItem.target = self
                    menu.insertItem(addValueItem, at: 2)
                }
            }

            if let header = contextHeader {
                menu.insertItem(.separator(), at: 0)
                let title = parent.manuallyStruckHeaderIDs.contains(header.id)
                    ? Localizer.text(.restoreCurrentHeader, language: parent.language)
                    : Localizer.text(.strikeCurrentHeader, language: parent.language)
                let toggleItem = NSMenuItem(title: title, action: #selector(toggleContextHeaderStrike), keyEquivalent: "")
                toggleItem.target = self
                menu.insertItem(toggleItem, at: 0)

                let addNameItem = NSMenuItem(title: Localizer.text(.addHeaderNameAsKeyword, language: parent.language), action: #selector(addHeaderNameAsKeyword), keyEquivalent: "")
                addNameItem.target = self
                menu.insertItem(addNameItem, at: 1)

                if !header.value.isEmpty {
                    let addValueItem = NSMenuItem(title: Localizer.text(.addHeaderValueAsKeyword, language: parent.language), action: #selector(addHeaderValueAsKeyword), keyEquivalent: "")
                    addValueItem.target = self
                    menu.insertItem(addValueItem, at: 2)
                }
            }

            let selectedRange = view.selectedRange()
            if selectedRange.length > 0 {
                let selectedText = (view.string as NSString)
                    .substring(with: selectedRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !selectedText.isEmpty {
                    contextKeyword = selectedText
                    contextImportantHeaderName = HeaderInspector.headerName(in: view.string, selectedUTF16Range: selectedRange)
                    menu.insertItem(.separator(), at: 0)
                    if contextImportantHeaderName != nil {
                        let importantItem = NSMenuItem(title: Localizer.text(.addSelectedHeaderAsImportant, language: parent.language), action: #selector(addSelectedHeaderAsImportant), keyEquivalent: "")
                        importantItem.target = self
                        menu.insertItem(importantItem, at: 0)
                    }
                    let keywordItem = NSMenuItem(title: Localizer.text(.addSelectedTextAsKeyword, language: parent.language), action: #selector(addSelectedTextAsKeyword), keyEquivalent: "")
                    keywordItem.target = self
                    menu.insertItem(keywordItem, at: 0)
                }
            }

            return menu
        }

        @objc private func toggleContextHeaderStrike() {
            guard let contextHeader else { return }
            parent.toggleHeaderStrike(contextHeader)
        }

        @objc private func toggleContextQueryParameterStrike() {
            guard let contextQueryParameter else { return }
            parent.toggleQueryParameterStrike(contextQueryParameter)
        }

        @objc private func addHeaderNameAsKeyword() {
            guard let contextHeader else { return }
            parent.addRedactionKeyword(contextHeader.name)
        }

        @objc private func addHeaderValueAsKeyword() {
            guard let contextHeader else { return }
            parent.addRedactionKeyword(contextHeader.value)
        }

        @objc private func addQueryParameterNameAsKeyword() {
            guard let contextQueryParameter else { return }
            parent.addRedactionKeyword(contextQueryParameter.name)
        }

        @objc private func addQueryParameterValueAsKeyword() {
            guard let value = contextQueryParameter?.value else { return }
            parent.addRedactionKeyword(value)
        }

        @objc private func addSelectedTextAsKeyword() {
            guard let contextKeyword else { return }
            parent.addRedactionKeyword(contextKeyword)
        }

        @objc private func addSelectedHeaderAsImportant() {
            guard let contextImportantHeaderName else { return }
            parent.addImportantHeaderName(contextImportantHeaderName)
        }

        func applyHighlighting() {
            let started = Date()
            guard let textView = textView else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let storage = textView.textStorage!

            storage.beginEditing()

            // 重置为默认样式
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: fullRange)

            for highlight in parent.riskHighlights {
                guard let range = TextLineRanges.range(forLineNumber: highlight.line, in: text),
                      range.location != NSNotFound,
                      range.location + range.length <= fullRange.length else { continue }
                storage.addAttributes([
                    .backgroundColor: Self.backgroundColor(for: highlight.severity)
                ], range: range)
            }

            // 高亮第一行（请求行）：Method 加粗蓝色
            let lines = text.components(separatedBy: "\n")
            if let firstLine = lines.first {
                let parts = firstLine.split(separator: " ", maxSplits: 1)
                if let method = parts.first {
                    let methodRange = NSRange(location: 0, length: method.count)
                    storage.addAttributes([
                        .foregroundColor: NSColor.systemBlue,
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
                    ], range: methodRange)
                }
            }

            // 高亮 Header names（行首到 : 之前）
            let headerPattern = #"^([A-Za-z][\w-]*):"#
            if let regex = try? NSRegularExpression(pattern: headerPattern, options: .anchorsMatchLines) {
                let matches = regex.matches(in: text, range: fullRange)
                for match in matches {
                    let nameRange = match.range(at: 1)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: nameRange)
                }
            }

            applyJSONHighlighting(in: storage, text: text)

            // 直接在原始请求文本里划掉不会发出的 Header
            for item in headerLineRanges(in: text) where item.header.isStruck {
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.systemRed,
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: item.range)
            }

            let queryKeywords = parent.redactMatchingHeaders ? parent.redactionKeywords : []
            for item in QueryParameterInspector.parameterRanges(
                in: text,
                manuallyStruckIDs: parent.manuallyStruckQueryParameterIDs,
                keywords: queryKeywords
            ) where item.parameter.isStruck {
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.systemRed,
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: item.range)
            }

            // 高亮 {{变量}}
            let varPattern = #"\{\{[^}]+\}\}"#
            if let regex = try? NSRegularExpression(pattern: varPattern) {
                let matches = regex.matches(in: text, range: fullRange)
                for match in matches {
                    storage.addAttributes([
                        .foregroundColor: NSColor.systemOrange,
                        .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.1)
                    ], range: match.range)
                }
            }

            // 高亮搜索结果
            for (index, match) in parent.searchMatches.enumerated() {
                let isSelected = index == parent.selectedSearchMatchIndex
                storage.addAttributes([
                    .backgroundColor: isSelected
                        ? NSColor.systemYellow.withAlphaComponent(0.65)
                        : NSColor.systemYellow.withAlphaComponent(0.28)
                ], range: match.range)
            }

            storage.endEditing()

            if let selectedIndex = parent.selectedSearchMatchIndex,
               parent.searchMatches.indices.contains(selectedIndex) {
                textView.setSelectedRange(parent.searchMatches[selectedIndex].range)
                TextViewNavigator.center(parent.searchMatches[selectedIndex].range, in: textView)
            }

            PerformanceLogStore.appendIfSlow(
                operation: "highlight",
                source: "request",
                elapsed: Date().timeIntervalSince(started),
                textLength: fullRange.length,
                queryLength: (parent.searchText as NSString).length,
                matchCount: parent.searchMatches.count
            )
        }

        private func applyJSONHighlighting(in storage: NSTextStorage, text: String) {
            for token in jsonTokens(in: text) {
                storage.addAttributes(Self.jsonAttributes(for: token.kind), range: token.range)
            }
        }

        private func jsonTokens(in text: String) -> [JSONSyntaxToken] {
            let bodyRange = HTTPMessageRanges.bodyRange(in: text)
            if text == cachedJSONText, bodyRange == cachedJSONBodyRange {
                return cachedJSONTokens
            }

            cachedJSONText = text
            cachedJSONBodyRange = bodyRange
            cachedJSONTokens = bodyRange.map { JSONSyntaxHighlighter.tokenRanges(in: text, range: $0) } ?? []
            return cachedJSONTokens
        }

        private func headerLineRanges(in rawText: String) -> [(header: HeaderLine, range: NSRange)] {
            let text = rawText as NSString
            guard text.length > 0 else { return [] }

            let keywords = parent.redactMatchingHeaders ? parent.redactionKeywords : []
            let normalizedKeywords = keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            var result: [(HeaderLine, NSRange)] = []
            var scanLocation = 0
            var headerIndex = 0
            var lineNumber = 0

            while scanLocation < text.length {
                let lineRange = text.lineRange(for: NSRange(location: scanLocation, length: 0))
                let rawLine = text.substring(with: lineRange)
                let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
                defer {
                    scanLocation = lineRange.location + lineRange.length
                    lineNumber += 1
                }

                if lineNumber == 0 {
                    continue
                }
                if line.isEmpty {
                    break
                }
                guard let colonIndex = line.firstIndex(of: ":") else {
                    continue
                }

                let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }

                let id = HeaderInspector.headerID(index: headerIndex, name: name, value: value)
                let haystack = "\(name)\n\(value)".lowercased()
                let keywordMatched = normalizedKeywords.contains { haystack.contains($0) }
                let header = HeaderLine(
                    id: id,
                    name: name,
                    value: value,
                    isStruck: parent.manuallyStruckHeaderIDs.contains(id) || keywordMatched
                )
                let visibleLength = (line as NSString).length
                result.append((header, NSRange(location: lineRange.location, length: visibleLength)))
                headerIndex += 1
            }

            return result
        }

        private static func backgroundColor(for severity: String) -> NSColor {
            switch severity.lowercased() {
            case "high":
                return NSColor.systemRed.withAlphaComponent(0.18)
            case "low":
                return NSColor.systemBlue.withAlphaComponent(0.12)
            default:
                return NSColor.systemOrange.withAlphaComponent(0.16)
            }
        }

        private static func jsonAttributes(for kind: JSONSyntaxToken.Kind) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .key:
                return [
                    .foregroundColor: NSColor.systemPurple,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                ]
            case .string:
                return [.foregroundColor: NSColor.systemGreen]
            case .number:
                return [.foregroundColor: NSColor.systemBlue]
            case .literal:
                return [.foregroundColor: NSColor.systemOrange]
            case .punctuation:
                return [.foregroundColor: NSColor.secondaryLabelColor]
            }
        }
    }
}
