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
                    .environment(\.refreshIssueDetails, refreshIssueDetails)
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

    private func refreshIssueDetails() {
        Task {
            await loadIssueDetails()
        }
    }
}

// MARK: - Issue Detail View

struct IssueDetailView: View {
    let issueDetails: IssueDetails
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.refreshIssueDetails) var refreshIssueDetails
    @State private var selectedTab = 0
    @State private var newCommentText = ""
    @State private var isSubmittingComment = false

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
                if let resolution = issueDetails.issue.resolution {
                    metadataItem(label: "Resolution", value: resolution, color: .green)
                }
                metadataItem(label: "Assignee", value: issueDetails.issue.assignee ?? "Unassigned", color: .secondary)
                if let priority = issueDetails.issue.priority {
                    metadataItem(label: "Priority", value: priority, color: priorityColor(for: priority))
                }
                metadataItem(label: "Project", value: issueDetails.issue.project, color: .secondary)
                IssueSprintSelector(issue: issueDetails.issue)
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
            HStack(alignment: .top, spacing: 40) {
                // Left column - Information
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

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right column - Editable fields
                VStack(alignment: .leading, spacing: 20) {
                    // Parent (Epic)
                    IssueEpicSelector(issue: issueDetails.issue)

                    // Estimate
                    IssueEstimateEditor(issue: issueDetails.issue)

                    // Log Time
                    IssueLogTimeButton(issue: issueDetails.issue)

                    Spacer()
                }
                .frame(width: 250, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    // Group comments into threads (parent comments with their replies)
    private var threadedComments: [(parent: IssueComment, replies: [IssueComment])] {
        let parentComments = issueDetails.comments.filter { $0.parentId == nil }
        let replyComments = issueDetails.comments.filter { $0.parentId != nil }

        // Create a lookup of replies by parentId
        var repliesByParent: [String: [IssueComment]] = [:]
        for reply in replyComments {
            if let parentId = reply.parentId {
                repliesByParent[parentId, default: []].append(reply)
            }
        }

        return parentComments.map { parent in
            (parent: parent, replies: repliesByParent[parent.id] ?? [])
        }
    }

    private var commentsTab: some View {
        VStack(spacing: 0) {
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
                        ForEach(threadedComments, id: \.parent.id) { thread in
                            VStack(alignment: .leading, spacing: 4) {
                                // Parent comment with reply callback
                                CommentView(comment: thread.parent, jiraService: jiraService, onReply: { replyText in
                                    submitReply(to: thread.parent.id, text: replyText)
                                })

                                // Replies indented under parent
                                ForEach(thread.replies) { reply in
                                    CommentView(comment: reply, jiraService: jiraService, isReply: true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }

            Divider()

            // Add comment input
            HStack(alignment: .bottom, spacing: 8) {
                MentionTextField(
                    placeholder: "Add a comment...",
                    text: $newCommentText,
                    jiraService: jiraService,
                    onSubmit: submitComment
                )

                Button(action: submitComment) {
                    if isSubmittingComment {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingComment)
            }
            .padding(12)
        }
    }

    private func submitComment() {
        let commentText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commentText.isEmpty else { return }

        isSubmittingComment = true

        Task {
            let success = await jiraService.addComment(issueKey: issueDetails.issue.key, comment: commentText)

            await MainActor.run {
                isSubmittingComment = false
                if success {
                    newCommentText = ""
                    refreshIssueDetails()
                }
            }
        }
    }

    private func submitReply(to parentId: String, text: String) {
        Task {
            let success = await jiraService.addComment(
                issueKey: issueDetails.issue.key,
                comment: text,
                parentId: parentId
            )

            await MainActor.run {
                if success {
                    refreshIssueDetails()
                }
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
    let jiraService: JiraService
    var isReply: Bool = false
    var onReply: ((String) -> Void)? = nil

    @State private var isReplying = false
    @State private var replyText = ""
    @State private var isSubmitting = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Indentation and thread line for replies
            if isReply {
                VStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 2)
                }
                .frame(width: 24)
                .padding(.leading, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isReply ? "arrowshape.turn.up.left.fill" : "person.circle.fill")
                        .font(.system(size: isReply ? 12 : 16))
                        .foregroundColor(isReply ? .secondary : .blue)

                    Text(comment.author)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(formatDate(comment.created))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Reply button (only show for parent comments, not replies)
                    if !isReply && onReply != nil {
                        Button(action: { isReplying.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 11))
                                Text("Reply")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(isReplying ? 0 : 1)
                    }
                }

                Text(comment.body)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(isReply ? 0.2 : 0.3))
                    .cornerRadius(8)

                // Inline reply input
                if isReplying {
                    HStack(alignment: .bottom, spacing: 8) {
                        MentionTextField(
                            placeholder: "Write a reply...",
                            text: $replyText,
                            jiraService: jiraService,
                            onSubmit: submitReply
                        )

                        Button(action: submitReply) {
                            if isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

                        Button(action: {
                            isReplying = false
                            replyText = ""
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor).opacity(isReply ? 0.5 : 1.0))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(isReply ? 0.1 : 0.2), lineWidth: 1)
            )
        }
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

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let onReply = onReply else { return }

        isSubmitting = true
        onReply(text)

        // Reset state after callback (the parent will handle refresh)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSubmitting = false
            isReplying = false
            replyText = ""
        }
    }
}

// MARK: - Issue Sprint Selector

struct IssueSprintSelector: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails
    @State private var selectedSprintName: String = ""
    @State private var isEditing: Bool = false
    @State private var searchText: String = ""

    private var currentSprintName: String {
        if let sprints = issue.fields.customfield_10020, !sprints.isEmpty, let firstSprint = sprints.first {
            return firstSprint.name
        }
        return "Backlog"
    }

    private var projectSprints: [JiraSprint] {
        // Filter sprints to only those from this project
        let allSprints = jiraService.availableSprints
        let projectKey = issue.fields.project.key

        Logger.shared.info("IssueSprintSelector: Filtering sprints for issue \(issue.key) in project '\(issue.project)' (key: \(projectKey))")
        Logger.shared.info("IssueSprintSelector: Total available sprints: \(allSprints.count)")
        Logger.shared.info("IssueSprintSelector: Sprint project map has \(jiraService.sprintProjectMap.count) entries")

        // Try to filter by project using sprintProjectMap
        let filtered = allSprints.filter { sprint in
            if let projects = jiraService.sprintProjectMap[sprint.id] {
                let matches = projects.contains(projectKey)
                Logger.shared.info("IssueSprintSelector: Sprint \(sprint.id) (\(sprint.name)) mapped to projects: \(projects.joined(separator: ", ")) - matches: \(matches)")
                return matches
            }
            // Fallback: check if sprint name contains project key
            let matches = sprint.name.uppercased().contains(projectKey.uppercased())
            Logger.shared.info("IssueSprintSelector: Sprint \(sprint.id) (\(sprint.name)) not in map, using name match: \(matches)")
            return matches
        }

        Logger.shared.info("IssueSprintSelector: Filtered to \(filtered.count) sprints for project \(projectKey)")

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
            let success = await jiraService.moveIssueToSprint(
                issueKey: issue.key,
                sprintId: sprint?.id
            )

            if success {
                Logger.shared.info("Updated sprint for \(issue.key) to \(sprint?.name ?? "Backlog")")
                await MainActor.run {
                    refreshIssueDetails()
                }
            } else {
                Logger.shared.error("Failed to update sprint for \(issue.key)")
            }
        }
    }
}

// MARK: - Issue Epic Selector

struct IssueEpicSelector: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails
    @State private var searchText: String = ""
    @State private var availableEpics: [String: String] = [:] // epic key -> summary
    @State private var isLoading = false
    @State private var showingPicker = false

    private var currentEpicKey: String? {
        issue.fields.customfield_10014
    }

    private var currentEpicDisplay: String {
        if let epicKey = currentEpicKey {
            if let summary = availableEpics[epicKey] {
                return "\(epicKey): \(summary)"
            }
            return epicKey
        }
        return "None"
    }

    private var filteredEpics: [(key: String, summary: String)] {
        let epics = availableEpics.map { (key: $0.key, summary: $0.value) }
        if searchText.isEmpty {
            return epics.sorted { $0.key > $1.key }
        }
        return epics.filter {
            $0.key.lowercased().contains(searchText.lowercased()) ||
            $0.summary.lowercased().contains(searchText.lowercased())
        }.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Button(action: {
                showingPicker.toggle()
            }) {
                HStack {
                    Text(currentEpicDisplay)
                        .font(.system(size: 12))
                        .foregroundColor(currentEpicKey == nil ? .secondary : .purple)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPicker, arrowEdge: .trailing) {
                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        TextField("Search epics...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Epic list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // None option
                            Button(action: {
                                updateEpic(to: nil)
                                showingPicker = false
                            }) {
                                Text("None")
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(currentEpicKey == nil ? Color.accentColor.opacity(0.1) : Color.clear)

                            Divider()

                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading epics...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            } else if filteredEpics.isEmpty {
                                Text(searchText.isEmpty ? "No epics available" : "No epics found")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                ForEach(filteredEpics, id: \.key) { epic in
                                    Button(action: {
                                        updateEpic(to: epic.key)
                                        showingPicker = false
                                        searchText = ""
                                    }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(epic.key)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Text(epic.summary)
                                                .font(.system(size: 12))
                                                .foregroundColor(.primary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                    .background(currentEpicKey == epic.key ? Color.accentColor.opacity(0.1) : Color.clear)

                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(width: 300, height: 250)
                }
            }
        }
        .task {
            await loadEpics()
        }
    }

    private func loadEpics() async {
        isLoading = true
        let projectName = issue.project

        // Build JQL to find all epics in this project
        let jql = "project = \"\(projectName)\" AND type = Epic AND resolution = Unresolved ORDER BY created DESC"

        var components = URLComponents(string: "\(jiraService.config.jiraBaseURL)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "summary")
        ]

        guard let url = components.url else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        let credentials = "\(jiraService.config.jiraEmail):\(jiraService.config.jiraAPIKey)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.shared.error("Failed to fetch epics")
                isLoading = false
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let issues = json["issues"] as? [[String: Any]] {
                var epics: [String: String] = [:]
                for issue in issues {
                    if let key = issue["key"] as? String,
                       let fields = issue["fields"] as? [String: Any],
                       let summary = fields["summary"] as? String {
                        epics[key] = summary
                    }
                }
                await MainActor.run {
                    self.availableEpics = epics
                }
            }
        } catch {
            Logger.shared.error("Error fetching epics: \(error)")
        }

        isLoading = false
    }

    private func updateEpic(to epicKey: String?) {
        Task {
            let success = await jiraService.updateIssue(
                issueKey: issue.key,
                fields: epicKey == nil ? ["customfield_10014": NSNull()] : ["epic": epicKey!]
            )

            if success {
                Logger.shared.info("Updated epic for \(issue.key) to \(epicKey ?? "None")")
                await MainActor.run {
                    refreshIssueDetails()
                }
            } else {
                Logger.shared.error("Failed to update epic for \(issue.key)")
            }
        }
    }
}

// MARK: - Issue Estimate Editor

struct IssueEstimateEditor: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails
    @State private var isEditing = false
    @State private var editValue: String = ""

    private var currentEstimate: String {
        if let seconds = issue.fields.timeoriginalestimate {
            return formatTime(seconds: seconds)
        }
        return "None"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimate")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            if isEditing {
                HStack(spacing: 6) {
                    TextField("e.g., 2h, 30m, 1d", text: $editValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button(action: saveEstimate) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)

                    Button(action: { isEditing = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: {
                    editValue = currentEstimate == "None" ? "" : currentEstimate
                    isEditing = true
                }) {
                    HStack {
                        Text(currentEstimate)
                            .font(.system(size: 12))
                            .foregroundColor(currentEstimate == "None" ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours >= 8 {
            let days = hours / 8
            let remainingHours = hours % 8
            if remainingHours == 0 {
                return "\(days)d"
            }
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        }
        return "0m"
    }

    private func saveEstimate() {
        guard !editValue.isEmpty else {
            isEditing = false
            return
        }

        Task {
            let success = await jiraService.updateIssue(
                issueKey: issue.key,
                fields: ["originalEstimate": editValue]
            )

            await MainActor.run {
                if success {
                    Logger.shared.info("Updated estimate for \(issue.key) to \(editValue)")
                    isEditing = false
                    refreshIssueDetails()
                } else {
                    Logger.shared.error("Failed to update estimate for \(issue.key)")
                }
            }
        }
    }
}

// MARK: - Issue Log Time Button

struct IssueLogTimeButton: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @State private var showingLogWork = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log Time")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Button(action: {
                showingLogWork = true
            }) {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text("Log work")
                        .font(.system(size: 12))
                    Spacer()
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingLogWork) {
                LogWorkView(issue: issue, isPresented: $showingLogWork)
                    .environmentObject(jiraService)
            }
        }
    }
}

// MARK: - Environment Key for Refresh

struct RefreshIssueDetailsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var refreshIssueDetails: () -> Void {
        get { self[RefreshIssueDetailsKey.self] }
        set { self[RefreshIssueDetailsKey.self] = newValue }
    }
}
