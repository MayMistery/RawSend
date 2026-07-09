import SwiftUI

struct HeaderSummaryView: View {
    @EnvironmentObject var appState: AppState
    let title: String
    let headers: [HeaderLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pin")
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            if headers.isEmpty {
                Text(appState.t(.noImportantHeaderHit))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(headers) { header in
                            HeaderChipView(header: header)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct HeaderChipView: View {
    let header: HeaderLine

    var body: some View {
        HStack(spacing: 4) {
            Text(header.name)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            Text(header.value)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .textSelection(.enabled)
    }
}
