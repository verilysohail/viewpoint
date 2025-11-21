import SwiftUI

@main
struct ViewpointApp: App {
    @StateObject private var jiraService = JiraService()
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jiraService)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    checkFirstRun()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Indigo AI Assistant Window
        Window("Indigo", id: "indigo") {
            IndigoView(viewModel: IndigoViewModel(jiraService: jiraService))
                .environmentObject(jiraService)
                .frame(minWidth: 500, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 700)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .onDisappear {
                    // Mark setup as complete when settings are dismissed
                    if isConfigured() {
                        hasCompletedSetup = true
                    }
                }
        }
    }

    private func checkFirstRun() {
        // If not configured, open settings
        if !isConfigured() && !hasCompletedSetup {
            // Small delay to ensure main window is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    private func isConfigured() -> Bool {
        let baseURL = UserDefaults.standard.string(forKey: "jiraBaseURL") ?? ""
        let email = UserDefaults.standard.string(forKey: "jiraEmail") ?? ""
        let apiKey = KeychainHelper.load(key: "jiraAPIKey") ?? ""

        return !baseURL.isEmpty && !email.isEmpty && !apiKey.isEmpty
    }
}
