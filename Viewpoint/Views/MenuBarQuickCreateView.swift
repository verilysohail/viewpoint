import SwiftUI

struct MenuBarQuickCreateView: View {
    let jiraService: JiraService
    let dismissAction: () -> Void

    @AppStorage("defaultAssignee") private var defaultAssignee: String = ""
    @AppStorage("defaultProject") private var defaultProject: String = ""
    @AppStorage("defaultComponent") private var defaultComponent: String = ""
    @AppStorage("defaultEpic") private var defaultEpic: String = ""

    @State private var summary: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isSummaryFocused: Bool

    private var canCreate: Bool {
        !summary.isEmpty && !defaultProject.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.system(size: 16))
                Text("Quick Create Issue")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)

            // Text field
            TextField("Enter issue summary...", text: $summary)
                .textFieldStyle(.roundedBorder)
                .focused($isSummaryFocused)
                .onSubmit {
                    if canCreate {
                        createIssue()
                    }
                }
                .onExitCommand {
                    dismissAction()
                }

            // Project info or error
            if !defaultProject.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(defaultProject)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("No default project set")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Creating indicator
            if isCreating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("Creating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            isSummaryFocused = true
        }
    }

    private func createIssue() {
        guard canCreate else { return }

        isCreating = true
        errorMessage = nil

        Task {
            var fields: [String: Any] = [
                "project": defaultProject,
                "summary": summary,
                "type": "Story" // Default to Story
            ]

            if !defaultAssignee.isEmpty {
                fields["assignee"] = defaultAssignee
            }

            if !defaultComponent.isEmpty {
                fields["components"] = [defaultComponent]
            }

            if !defaultEpic.isEmpty {
                fields["epic"] = defaultEpic
            }

            let (success, issueKey) = await jiraService.createIssue(fields: fields)

            await MainActor.run {
                isCreating = false

                if success {
                    Logger.shared.info("Created issue from menu bar: \(issueKey ?? "unknown")")
                    // Clear the field
                    summary = ""
                    // Refresh issues to show the new one
                    Task {
                        await jiraService.fetchMyIssues(updateAvailableOptions: false)
                    }
                    // Close the popover after a brief success moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismissAction()
                    }
                } else {
                    errorMessage = "Failed to create issue"
                }
            }
        }
    }
}
