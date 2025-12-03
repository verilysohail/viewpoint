import SwiftUI

// MARK: - Window Wrapper

struct IssueDetailWindowWrapper: View {
    let issueKey: String
    let jiraService: JiraService

    @State private var issueDetails: IssueDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading \(issueKey)...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Error loading issue")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let issueDetails = issueDetails {
                IssueDetailView(issueDetails: issueDetails)
                    .environmentObject(jiraService)
            }
        }
        .task {
            await loadIssueDetails()
        }
    }

    private func loadIssueDetails() async {
        isLoading = true
        errorMessage = nil

        let result = await jiraService.fetchIssueDetails(issueKey: issueKey)

        if result.success, let details = result.details {
            issueDetails = details
        } else {
            errorMessage = "Failed to load issue details for \(issueKey)"
        }

        isLoading = false
    }
}

// MARK: - Issue Detail View

struct IssueDetailView: View {
    let issueDetails: IssueDetails
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Details").tag(0)
                Text("Comments (\(issueDetails.comments.count))").tag(1)
                Text("History").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    detailsTab
                case 1:
                    commentsTab
                case 2:
                    historyTab
                default:
                    detailsTab
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Issue key and type
            HStack {
                Text(issueDetails.issue.key)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)

                Text(issueDetails.issue.issueType)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                // Open in browser button
                Button(action: {
                    if let url = URL(string: "\(Configuration.shared.jiraBaseURL)/browse/\(issueDetails.issue.key)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open in Jira")
                }
            }

            // Summary
            Text(issueDetails.issue.summary)
                .font(.system(size: 16))
                .foregroundColor(.primary)

            // Metadata row
            HStack(spacing: 20) {
                metadataItem(label: "Status", value: issueDetails.issue.status, color: statusColor(for: issueDetails.issue.status))
                metadataItem(label: "Assignee", value: issueDetails.issue.assignee ?? "Unassigned", color: .secondary)
                if let priority = issueDetails.issue.priority {
                    metadataItem(label: "Priority", value: priority, color: priorityColor(for: priority))
                }
                metadataItem(label: "Project", value: issueDetails.issue.project, color: .secondary)
                SprintSelector(issue: issueDetails.issue)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private func metadataItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
    }

    private var detailsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Description
                if let description = issueDetails.description {
                    DetailSection(title: "Description") {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }

                // Time tracking
                if let originalEstimate = issueDetails.issue.fields.timeoriginalestimate,
                   let timeSpent = issueDetails.issue.fields.timespent {
                    DetailSection(title: "Time Tracking") {
                        HStack(spacing: 30) {
                            timeItem(label: "Original Estimate", seconds: originalEstimate)
                            timeItem(label: "Time Spent", seconds: timeSpent)
                            if let remaining = issueDetails.issue.fields.timeestimate {
                                timeItem(label: "Remaining", seconds: remaining)
                            }
                        }
                    }
                }

                // Components
                if !issueDetails.issue.fields.components.isEmpty {
                    DetailSection(title: "Components") {
                        HStack(spacing: 8) {
                            ForEach(issueDetails.issue.fields.components, id: \.name) { component in
                                Text(component.name)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Dates
                DetailSection(title: "Dates") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let created = issueDetails.issue.created {
                            HStack {
                                Text("Created:")
                                    .foregroundColor(.secondary)
                                Text(formatDate(created))
                                    .foregroundColor(.primary)
                            }
                        }
                        if let updated = issueDetails.issue.updated {
                            HStack {
                                Text("Updated:")
                                    .foregroundColor(.secondary)
                                Text(formatDate(updated))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    private var commentsTab: some View {
        ScrollView {
            if issueDetails.comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No comments yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(60)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(issueDetails.comments) { comment in
                        CommentView(comment: comment)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
    }

    private var historyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(issueDetails.changelog)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeItem(label: String, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(formatTime(seconds: seconds))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
    }

    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case let s where s.contains("done") || s.contains("closed"):
            return .green
        case let s where s.contains("progress"):
            return .blue
        case let s where s.contains("review"):
            return .orange
        default:
            return .gray
        }
    }

    private func priorityColor(for priority: String) -> Color {
        switch priority.lowercased() {
        case "highest", "high":
            return .red
        case "medium":
            return .orange
        case "low", "lowest":
            return .blue
        default:
            return .gray
        }
    }
}

// MARK: - Supporting Views

struct DetailSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            content()
        }
    }
}

struct CommentView: View {
    let comment: IssueComment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)

                Text(comment.author)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(formatDate(comment.created))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }

            Text(comment.body)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: isoString) else {
            return isoString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - Sprint Selector

struct SprintSelector: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @State private var selectedSprintName: String = ""
    @State private var isEditing: Bool = false
    @State private var searchText: String = ""

    private var currentSprintName: String {
        if let sprints = issue.fields.sprint, !sprints.isEmpty, let firstSprint = sprints.first {
            return firstSprint.name
        }
        return "Backlog"
    }

    private var projectSprints: [JiraSprint] {
        // Filter sprints to only those from this project
        let allSprints = jiraService.availableSprints

        // Try to filter by project using sprintProjectMap
        let filtered = allSprints.filter { sprint in
            if let projects = jiraService.sprintProjectMap[sprint.id] {
                return projects.contains(issue.project)
            }
            // Fallback: check if sprint name contains project key
            return sprint.name.uppercased().contains(issue.project.uppercased())
        }

        return filtered.sorted { $0.id > $1.id } // Most recent first
    }

    private var filteredSprints: [JiraSprint] {
        if searchText.isEmpty {
            return projectSprints
        }
        return projectSprints.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sprint")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Menu {
                Button("Backlog") {
                    updateSprint(to: nil)
                }

                Divider()

                TextField("Search sprints...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8)

                Divider()

                ForEach(filteredSprints) { sprint in
                    Button(sprint.name) {
                        updateSprint(to: sprint)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentSprintName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentSprintName == "Backlog" ? .gray : .orange)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func updateSprint(to sprint: JiraSprint?) {
        Task {
            var updateFields: [String: Any] = [:]

            if let sprint = sprint {
                updateFields["sprint"] = "\(sprint.id)"
            } else {
                // Moving to backlog - remove from sprint
                updateFields["sprint"] = NSNull()
            }

            let success = await jiraService.updateIssue(
                issueKey: issue.key,
                fields: updateFields
            )

            if success {
                Logger.shared.info("Updated sprint for \(issue.key) to \(sprint?.name ?? "Backlog")")
            } else {
                Logger.shared.error("Failed to update sprint for \(issue.key)")
            }
        }
    }
}
