import SwiftUI

@main
struct RawSendApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {} // 禁用 ⌘N
            CommandMenu(appState.t(.request)) {
                Button(appState.t(.send)) { appState.sendRequest() }
                    .keyboardShortcut(.return, modifiers: .command)
                Divider()
                Button(appState.t(.search)) { appState.focusActiveSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Button(appState.t(.searchRequest)) { appState.focusRequestSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button(appState.t(.searchResponse)) { appState.focusResponseSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button(appState.t(.clearEditor)) { appState.rawText = "" }
                    .keyboardShortcut("l", modifiers: .command)
                Button(appState.t(.exportCurlHelp)) { appState.exportCurl() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandMenu(appState.t(.environment)) {
                Button(appState.t(.switchEnvironment)) { appState.showEnvironmentPicker = true }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
