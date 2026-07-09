import SwiftUI

// MARK: - Settings panel

/// Settings panel with custom sidebar navigation and content area.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .defaultHeaders
    private let sidebarWidth: CGFloat = 176

    enum SettingsTab: CaseIterable {
        case defaultHeaders
        case environments
        case general

        var icon: String {
            switch self {
            case .defaultHeaders: return "list.bullet.rectangle"
            case .environments: return "curlybraces"
            case .general: return "gearshape"
            }
        }

        func title(language: AppLanguage) -> String {
            switch self {
            case .defaultHeaders: return Localizer.text(.defaultHeaders, language: language)
            case .environments: return Localizer.text(.environments, language: language)
            case .general: return Localizer.text(.general, language: language)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 18)
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                            Text(tab.title(language: appState.appLanguage))
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .allowsTightening(true)
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: sidebarWidth)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch selectedTab {
                case .defaultHeaders:
                    DefaultHeadersSettingsView()
                case .environments:
                    EnvironmentsSettingsView()
                case .general:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 480)
        .onDisappear {
            appState.saveAll()
        }
    }
}

// MARK: - Default Headers

struct DefaultHeadersSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.t(.globalDefaultHeaders))
                    .font(.headline)
                Text(appState.t(.defaultHeadersDescription))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($appState.defaultHeaders) { $header in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $header.isEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                                .frame(width: 36)

                            TextField(appState.t(.fieldName), text: $header.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .font(.system(size: 12, design: .monospaced))

                            TextField(appState.t(.fieldValue), text: $header.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            Button(action: {
                                appState.defaultHeaders.removeAll(where: { $0.id == header.id })
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            Button(action: {
                appState.defaultHeaders.append(DefaultHeader())
            }) {
                Label(appState.t(.addHeader), systemImage: "plus")
                    .font(.system(size: 12))
            }
        }
        .padding(20)
    }
}

// MARK: - Environments

struct EnvironmentsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedEnvId: UUID?

    var selectedEnv: Binding<Environment>? {
        guard let id = selectedEnvId,
              let idx = appState.environments.firstIndex(where: { $0.id == id }) else { return nil }
        return $appState.environments[idx]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(appState.t(.environment))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(appState.environments) { env in
                            Button(action: { selectedEnvId = env.id }) {
                                Text(env.name)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(selectedEnvId == env.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                    )
                                    .foregroundColor(selectedEnvId == env.id ? .accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 4) {
                    Button(action: {
                        let newEnv = Environment(name: appState.t(.newEnvironmentName))
                        appState.environments.append(newEnv)
                        selectedEnvId = newEnv.id
                    }) {
                        Image(systemName: "plus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if let id = selectedEnvId {
                            appState.environments.removeAll(where: { $0.id == id })
                            selectedEnvId = appState.environments.first?.id
                        }
                    }) {
                        Image(systemName: "minus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.environments.count <= 1)

                    Spacer()
                }
            }
            .frame(width: 120)
            .padding(12)

            Divider()

            if let env = selectedEnv {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(appState.t(.environmentName), text: env.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium))

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(env.variables) { $variable in
                                HStack(spacing: 6) {
                                    TextField(appState.t(.fieldKey), text: $variable.key)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                        .font(.system(size: 12, design: .monospaced))

                                    Text("=")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))

                                    if variable.isSensitive {
                                        SecureField(appState.t(.fieldValue), text: $variable.value)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                    } else {
                                        TextField(appState.t(.fieldValue), text: $variable.value)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12, design: .monospaced))
                                    }

                                    Button(action: {
                                        $variable.wrappedValue.isSensitive.toggle()
                                    }) {
                                        Image(systemName: variable.isSensitive ? "lock.fill" : "lock.open")
                                            .font(.system(size: 11))
                                            .foregroundColor(variable.isSensitive ? .orange : .secondary)
                                            .frame(width: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .help(variable.isSensitive ? appState.t(.showValueHelp) : appState.t(.hideValueHelp))

                                    Button(action: {
                                        env.wrappedValue.variables.removeAll(where: { $0.id == variable.id })
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .frame(width: 20)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                    HStack(alignment: .top) {
                        Button(action: {
                            env.wrappedValue.variables.append(Environment.Variable())
                        }) {
                            Label(appState.t(.addVariable), systemImage: "plus")
                                .font(.system(size: 12))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(appState.t(.builtInVariables))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
                .padding(16)
            } else {
                VStack {
                    Text(appState.t(.selectEnvironment))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedEnvId == nil {
                selectedEnvId = appState.environments.first?.id
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t(.language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker(appState.t(.language), selection: $appState.preferences.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t(.network))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text(appState.t(.requestTimeout))
                            .font(.system(size: 13))
                        TextField("", value: $appState.preferences.timeoutSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text(appState.t(.timeoutSeconds))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Toggle(appState.t(.ignoreTLSErrors), isOn: $appState.preferences.ignoreTLSErrors)
                        .font(.system(size: 13))
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t(.history))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text(appState.t(.historyLimitPrefix))
                            .font(.system(size: 13))
                        TextField("", value: $appState.preferences.maxHistoryCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text(appState.t(.historyLimitSuffix))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t(.importantHeadersSection))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    ImportantHeaderSettingsView()
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t(.filterKeywords))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Toggle(appState.t(.filterSensitiveHeadersHelp), isOn: $appState.preferences.redactMatchingHeaders)
                        .font(.system(size: 13))

                    RedactionKeywordSettingsView()
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Codex")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(appState.t(.userPrompt))
                        .font(.system(size: 13))

                    TextEditor(text: $appState.preferences.codexUserPrompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )

                    Button(action: {
                        appState.preferences.codexUserPrompt = AppPreferences.defaultCodexUserPrompt
                    }) {
                        Label(appState.t(.resetDefault), systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t(.export))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Toggle(appState.t(.includeDefaultHeadersInCurl), isOn: $appState.preferences.includDefaultHeadersInCurl)
                        .font(.system(size: 13))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ImportantHeaderSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newHeaderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(appState.t(.headerNamePlaceholder), text: $newHeaderName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addHeaderName)

                Button(action: addHeaderName) {
                    Label(appState.t(.add), systemImage: "plus")
                        .font(.system(size: 12))
                }
                .disabled(newHeaderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(appState.preferences.importantHeaderNames.enumerated()), id: \.offset) { index, headerName in
                        HStack(spacing: 4) {
                            Text(headerName)
                                .font(.system(size: 11, design: .monospaced))
                            Button(action: {
                                appState.preferences.importantHeaderNames.remove(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
    }

    private func addHeaderName() {
        appState.addImportantHeaderName(newHeaderName)
        newHeaderName = ""
    }
}

private struct RedactionKeywordSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newKeyword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("token / auth / cookie", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addKeyword)

                Button(action: addKeyword) {
                    Label(appState.t(.add), systemImage: "plus")
                        .font(.system(size: 12))
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(appState.preferences.redactionKeywords.enumerated()), id: \.offset) { index, keyword in
                        HStack(spacing: 4) {
                            Text(keyword)
                                .font(.system(size: 11, design: .monospaced))
                            Button(action: {
                                appState.preferences.redactionKeywords.remove(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
    }

    private func addKeyword() {
        appState.addRedactionKeyword(newKeyword)
        newKeyword = ""
    }
}
