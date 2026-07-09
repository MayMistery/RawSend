import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView()

            Divider()

            // Main split: request editor + response panel
            HSplitView {
                RequestEditorView()
                    .frame(minWidth: 350)

                ResponsePanelView()
                    .frame(minWidth: 350)
            }

            Divider()

            // Status bar
            StatusBarView()
        }
        .frame(minWidth: 800, minHeight: 500)
            .onChange(of: appState.rawText) { _, _ in
            appState.updateParseStatus()
            appState.updateRequestSearchMatches(resetSelection: true)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showCodexChat) {
            CodexChatView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $appState.selectedEnvironmentId) {
                ForEach(appState.environments) { env in
                    Text(env.name).tag(Optional(env.id))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Divider().frame(height: 20)

            Button(action: { appState.sendRequest() }) {
                HStack(spacing: 4) {
                    if appState.isSending {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(appState.t(.send))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isSending || appState.parsedHost.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)

            Toggle("HTTP", isOn: $appState.sendHTTP)
                .toggleStyle(.checkbox)
            Toggle("HTTPS", isOn: $appState.sendHTTPS)
                .toggleStyle(.checkbox)
            Toggle(appState.t(.followRedirects), isOn: $appState.preferences.followRedirects)
                .toggleStyle(.checkbox)
                .help(appState.t(.followRedirectsHelp))

            Spacer()

            Button(action: { appState.showCodexChat = true }) {
                Label("Codex", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(appState.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: { appState.showHistory.toggle() }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .popover(isPresented: $appState.showHistory) {
                HistoryPopoverView()
                    .frame(width: 320, height: 400)
            }

            Button(action: { appState.exportCurl() }) {
                Image(systemName: "doc.on.clipboard")
            }
            .help(appState.t(.exportCurlHelp))

            Button(action: { appState.showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help(appState.t(.settingsHelp))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                Text(appState.t(.hostLabel))
                    .foregroundColor(.secondary)
                Text(appState.parsedHost.isEmpty ? appState.t(.hostMissing) : appState.parsedHost)
                    .foregroundColor(appState.parsedHost.isEmpty ? .red : .primary)
            }

            Divider().frame(height: 14)

            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text(appState.tf(.bodyBytes, appState.bodySize))
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 14)

            HStack(spacing: 4) {
                Image(systemName: "curlybraces")
                    .foregroundColor(.secondary)
                Text(appState.tf(.variables, appState.variableCount))
                    .foregroundColor(.secondary)
                if !appState.undefinedVars.isEmpty {
                    Text(appState.tf(.variablesUndefined, appState.undefinedVars.count))
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
