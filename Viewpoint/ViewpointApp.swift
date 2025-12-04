import SwiftUI
import AppKit

@main
struct ViewpointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var jiraService = JiraService()
    @StateObject private var viewsManager = ViewsManager()
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jiraService)
                .environmentObject(viewsManager)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    checkFirstRun()
                    appDelegate.configure(with: jiraService)
                    updateMenuBarIcon()
                }
                .onChange(of: showMenuBarIcon) { _ in
                    updateMenuBarIcon()
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

        // Issue Detail Windows (one per issue)
        WindowGroup(for: String.self) { $issueKey in
            if let issueKey = issueKey {
                IssueDetailWindowWrapper(issueKey: issueKey, jiraService: jiraService)
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 600)

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

    private func updateMenuBarIcon() {
        if let delegate = NSApp.delegate as? AppDelegate {
            if showMenuBarIcon {
                delegate.showMenuBar()
            } else {
                delegate.hideMenuBar()
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func configure(with jiraService: JiraService) {
        menuBarManager = MenuBarManager(jiraService: jiraService)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure app to stay running when all windows are closed
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running in background
        return false
    }

    func showMenuBar() {
        menuBarManager?.setupMenuBar()
    }

    func hideMenuBar() {
        menuBarManager?.removeMenuBar()
    }
}
