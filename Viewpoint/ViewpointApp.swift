import SwiftUI

@main
struct ViewpointApp: App {
    @StateObject private var jiraService = JiraService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jiraService)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
