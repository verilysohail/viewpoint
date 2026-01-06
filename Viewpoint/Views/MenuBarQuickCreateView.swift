import SwiftUI

class MenuBarQuickCreateViewModel: ObservableObject {
    @Published var summary: String = ""
    @Published var isCreating: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let jiraService: JiraService
    let dismissAction: () -> Void

    @AppStorage("defaultAssignee") var defaultAssignee: String = ""
    @AppStorage("defaultProject") var defaultProject: String = ""
    @AppStorage("defaultComponent") var defaultComponent: String = ""
    @AppStorage("defaultEpic") var defaultEpic: String = ""

    var canCreate: Bool {
        !summary.isEmpty && !defaultProject.isEmpty
    }

    init(jiraService: JiraService, dismissAction: @escaping () -> Void) {
        self.jiraService = jiraService
        self.dismissAction = dismissAction
    }

    func createIssue() {
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

                if success, let key = issueKey {
                    Logger.shared.info("Created issue from menu bar: \(key)")
                    // Show success message
                    successMessage = "Issue created: \(key)"
                    // Clear the field
                    summary = ""
                    errorMessage = nil
                    // Refresh issues to show the new one
                    Task {
                        await jiraService.fetchMyIssues(updateAvailableOptions: false)
                    }
                    // Close the popover after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.successMessage = nil
                        self?.dismissAction()
                    }
                } else {
                    errorMessage = "Failed to create issue"
                    successMessage = nil
                }
            }
        }
    }
}

struct MenuBarQuickCreateView: View {
    @ObservedObject var viewModel: MenuBarQuickCreateViewModel

    init(viewModel: MenuBarQuickCreateViewModel) {
        self.viewModel = viewModel
    }

    var defaultProject: String {
        viewModel.defaultProject
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

            // Text field - using custom NSTextField for reliable Enter key handling
            SubmittableTextField(
                "Enter issue summary...",
                text: $viewModel.summary,
                onSubmit: {
                    viewModel.createIssue()
                },
                onEscape: {
                    viewModel.dismissAction()
                },
                isBordered: true,
                focusOnAppear: true
            )

            // Project info or error
            if !viewModel.defaultProject.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(viewModel.defaultProject)
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

            if let error = viewModel.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            if let success = viewModel.successMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(success)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Creating indicator
            if viewModel.isCreating {
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
    }
}
