import SwiftUI

struct SearchToolbarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var query: String
    @Binding var selectedIndex: Int?
    let matchCount: Int
    var selectedMatch: SearchMatch?
    let placeholder: String
    var focusToken: Int = 0
    let previousAction: () -> Void
    let nextAction: () -> Void
    @FocusState private var isSearchFocused: Bool

    private var matchLabel: String {
        guard matchCount > 0, let selectedIndex, selectedIndex < matchCount else {
            return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "0/0"
        }
        return "\(selectedIndex + 1)/\(matchCount)"
    }

    private var positionLabel: String {
        guard let selectedMatch else { return "" }
        return "L\(selectedMatch.lineNumber):C\(selectedMatch.columnNumber)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onSubmit(nextAction)

            Text(matchLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)

            if !positionLabel.isEmpty {
                Text(positionLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 68, alignment: .trailing)
            }

            Button(action: previousAction) {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)
            .help(appState.t(.previousMatch))

            Button(action: nextAction) {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)
            .help(appState.t(.nextMatch))

            if !query.isEmpty {
                Button(action: {
                    query = ""
                    selectedIndex = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(appState.t(.clearSearch))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: focusToken) { _, _ in
            isSearchFocused = true
        }
    }
}
