import SwiftUI

/// 历史记录 Popover
struct HistoryPopoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    var filteredHistory: [HistoryItem] {
        if searchText.isEmpty {
            return appState.history
        }
        let query = searchText.lowercased()
        return appState.history.filter {
            $0.host.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.method.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(appState.t(.searchHistoryPlaceholder), text: $searchText)
                    .textFieldStyle(.plain)

                if !appState.history.isEmpty {
                    Button(appState.t(.clear)) {
                        appState.clearHistory()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(10)

            Divider()

            // 列表
            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? appState.t(.historyEmpty) : appState.t(.noMatches))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredHistory) { item in
                        Button {
                            appState.loadFromHistory(item)
                        } label: {
                            HistoryRow(item: item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.method) \(item.host)\(item.path)")
                        .accessibilityAction {
                                appState.loadFromHistory(item)
                        }
                    }
                    .onDelete { offsets in
                        let items = filteredHistory
                        let idsToDelete = offsets.map { items[$0].id }
                        appState.history.removeAll(where: { idsToDelete.contains($0.id) })
                        PersistenceManager.shared.saveHistory(appState.history)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - 历史行

struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 8) {
            // Method 标签
            Text(item.method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(methodColor)
                .cornerRadius(3)

            // 路径
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.host)\(item.path)")
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                Text(item.displayDate)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var methodColor: Color {
        switch item.method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
}
