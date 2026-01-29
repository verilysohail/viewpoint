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
    @State private var childIssues: [JiraIssue] = []
    @State private var isLoadingChildren = false
    @State private var showingTransitionFields = false
    @State private var pendingTransitionInfo: TransitionInfo?
    @State private var pendingTargetStatus: String = ""

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
                Text("Child Items (\(childIssues.count))").tag(3)
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
                case 3:
                    childItemsTab
                default:
                    detailsTab
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            await loadChildIssues()
        }
        .sheet(isPresented: $showingTransitionFields) {
            if let transitionInfo = pendingTransitionInfo {
                TransitionFieldsView(
                    issue: issueDetails.issue,
                    targetStatus: pendingTargetStatus,
                    transitionInfo: transitionInfo,
                    isPresented: $showingTransitionFields
                )
                .environmentObject(jiraService)
            }
        }
        .onChange(of: showingTransitionFields) { isShowing in
            // When the transition sheet closes, refresh the details
            if !isShowing {
                refreshIssueDetails()
            }
        }
    }

    private var statusDropdown: some View {
        Menu {
            ForEach(jiraService.availableStatuses.sorted(), id: \.self) { status in
                Button(action: {
                    Task {
                        await handleStatusChange(to: status)
                    }
                }) {
                    HStack {
                        Text(status)
                        if issueDetails.issue.status == status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(issueDetails.issue.status)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusColor(for: issueDetails.issue.status))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func handleStatusChange(to newStatus: String) async {
        // Check if this transition requires additional fields
        if let transitionInfo = await jiraService.getTransitionInfo(issueKey: issueDetails.issue.key, targetStatus: newStatus) {
            if transitionInfo.requiredFields.isEmpty {
                // No required fields, transition directly
                let _ = await jiraService.updateIssueStatus(issueKey: issueDetails.issue.key, newStatus: newStatus)
                // Refresh the detail view to show updated status
                await MainActor.run {
                    refreshIssueDetails()
                }
            } else {
                // Has required fields, show the dialog
                await MainActor.run {
                    pendingTransitionInfo = transitionInfo
                    pendingTargetStatus = newStatus
                    showingTransitionFields = true
                }
            }
        }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    statusDropdown
                }
                if let resolution = issueDetails.issue.resolution {
                    metadataItem(label: "Resolution", value: resolution, color: .green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assignee")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    UserSelector(issue: issueDetails.issue, fieldType: .assignee)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reporter")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    UserSelector(issue: issueDetails.issue, fieldType: .reporter)
                }
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

                    // PCM Master
                    PCMMasterSelector(issue: issueDetails.issue)

                    // Request Classification
                    RequestClassificationSelector(issue: issueDetails.issue)

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

    private var childItemsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoadingChildren {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading child items...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
                } else if childIssues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No child items found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(childItemsDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else {
                    ForEach(childIssues) { child in
                        ChildIssueRow(issue: child)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var childItemsDescription: String {
        let issueType = issueDetails.issue.issueType.lowercased()
        switch issueType {
        case "epic":
            return "Stories and tasks linked to this epic will appear here"
        case "story", "task":
            return "Subtasks of this \(issueDetails.issue.issueType) will appear here"
        case "initiative":
            return "Epics linked to this initiative will appear here"
        default:
            return "Child items will appear here"
        }
    }

    private func loadChildIssues() async {
        await MainActor.run { isLoadingChildren = true }

        let issueType = issueDetails.issue.issueType.lowercased()
        var jql: String

        switch issueType {
        case "epic":
            // For epics, find stories/tasks with this epic as parent
            jql = "\"Epic Link\" = \(issueDetails.issue.key) OR parent = \(issueDetails.issue.key) ORDER BY created DESC"
        case "story", "task", "bug":
            // For stories/tasks, find subtasks
            jql = "parent = \(issueDetails.issue.key) ORDER BY created DESC"
        case "initiative":
            // For initiatives, find child epics (assuming parent link)
            jql = "parent = \(issueDetails.issue.key) AND type = Epic ORDER BY created DESC"
        default:
            // Generic: look for subtasks or linked issues
            jql = "parent = \(issueDetails.issue.key) ORDER BY created DESC"
        }

        let children = await jiraService.fetchChildIssues(jql: jql)
        await MainActor.run {
            childIssues = children
            isLoadingChildren = false
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

struct ChildIssueRow: View {
    let issue: JiraIssue
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            // Issue type icon
            issueTypeIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                // Key and summary
                HStack {
                    Text(issue.key)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)

                    Text(issue.issueType)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(issueTypeColor.opacity(0.2))
                        .cornerRadius(3)
                }

                Text(issue.summary)
                    .font(.system(size: 13))
                    .lineLimit(2)
            }

            Spacer()

            // Status badge
            Text(issue.status)
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .cornerRadius(4)

            // Assignee
            if let assignee = issue.assignee {
                Text(assignee)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .onTapGesture(count: 2) {
            openWindow(value: issue.key)
        }
        .help("Double-click to open details")
    }

    private var issueTypeIcon: some View {
        let iconName: String
        let color: Color

        switch issue.issueType.lowercased() {
        case "bug":
            iconName = "ladybug.fill"
            color = .red
        case "story":
            iconName = "book.fill"
            color = .green
        case "task":
            iconName = "checkmark.square.fill"
            color = .blue
        case "subtask", "sub-task":
            iconName = "square.split.2x1.fill"
            color = .cyan
        case "epic":
            iconName = "bolt.fill"
            color = .purple
        default:
            iconName = "doc.fill"
            color = .gray
        }

        return Image(systemName: iconName)
            .foregroundColor(color)
    }

    private var issueTypeColor: Color {
        switch issue.issueType.lowercased() {
        case "bug": return .red
        case "story": return .green
        case "task": return .blue
        case "subtask", "sub-task": return .cyan
        case "epic": return .purple
        default: return .gray
        }
    }

    private var statusColor: Color {
        let status = issue.status.lowercased()
        if status.contains("done") || status.contains("closed") {
            return .green
        } else if status.contains("progress") {
            return .blue
        } else if status.contains("review") {
            return .orange
        }
        return .gray
    }
}

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

// MARK: - Issue Parent Selector

struct IssueEpicSelector: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails
    @State private var searchText: String = ""
    @State private var availableParents: [String: String] = [:] // parent key -> summary
    @State private var isLoading = false
    @State private var showingPicker = false

    /// Determine what type of parent to search for based on issue type
    private var parentType: String {
        switch issue.issueType.lowercased() {
        case "epic":
            return "Initiative"
        case "initiative":
            return "" // Initiatives typically don't have parents
        default:
            return "Epic" // Stories, Tasks, Bugs, Sub-tasks -> Epic
        }
    }

    /// Get current parent from either the parent field or epic link field
    private var currentParentKey: String? {
        // First check the parent field (used for Epic->Initiative hierarchy)
        if let parent = issue.fields.parent {
            return parent.key
        }
        // Fall back to epic link field (used for Story->Epic)
        return issue.fields.customfield_10014
    }

    private var currentParentDisplay: String {
        // Check parent field first
        if let parent = issue.fields.parent {
            if let details = parent.fields {
                return "\(parent.key): \(details.summary)"
            }
            return parent.key
        }
        // Fall back to epic link
        if let epicKey = issue.fields.customfield_10014 {
            if let summary = availableParents[epicKey] {
                return "\(epicKey): \(summary)"
            }
            return epicKey
        }
        return "None"
    }

    private var filteredParents: [(key: String, summary: String)] {
        let parents = availableParents.map { (key: $0.key, summary: $0.value) }
        if searchText.isEmpty {
            return parents.sorted { $0.key > $1.key }
        }
        return parents.filter {
            $0.key.lowercased().contains(searchText.lowercased()) ||
            $0.summary.lowercased().contains(searchText.lowercased())
        }.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            // Don't show picker for Initiatives (no parent type)
            if parentType.isEmpty {
                Text("N/A")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                Button(action: {
                    showingPicker.toggle()
                }) {
                    HStack {
                        Text(currentParentDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(currentParentKey == nil ? .secondary : .purple)
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
                            TextField("Search \(parentType.lowercased())s...", text: $searchText)
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

                        // Parent list
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // None option
                                Button(action: {
                                    updateParent(to: nil)
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
                                .background(currentParentKey == nil ? Color.accentColor.opacity(0.1) : Color.clear)

                                Divider()

                                if isLoading {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Loading \(parentType.lowercased())s...")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                } else if filteredParents.isEmpty {
                                    Text(searchText.isEmpty ? "No \(parentType.lowercased())s available" : "No \(parentType.lowercased())s found")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .padding()
                                } else {
                                    ForEach(filteredParents, id: \.key) { parent in
                                        Button(action: {
                                            updateParent(to: parent.key)
                                            showingPicker = false
                                            searchText = ""
                                        }) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(parent.key)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                Text(parent.summary)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.primary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                        .background(currentParentKey == parent.key ? Color.accentColor.opacity(0.1) : Color.clear)

                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 300, height: 250)
                }
            }
        }
        .task {
            await loadParents()
        }
    }

    private func loadParents() async {
        // Don't load if no parent type (Initiatives)
        guard !parentType.isEmpty else { return }

        isLoading = true
        let projectName = issue.project

        // Build JQL to find potential parents based on issue type
        let jql = "project = \"\(projectName)\" AND type = \(parentType) AND resolution = Unresolved ORDER BY created DESC"

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
                Logger.shared.error("Failed to fetch \(parentType.lowercased())s")
                isLoading = false
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let issues = json["issues"] as? [[String: Any]] {
                var parents: [String: String] = [:]
                for issue in issues {
                    if let key = issue["key"] as? String,
                       let fields = issue["fields"] as? [String: Any],
                       let summary = fields["summary"] as? String {
                        parents[key] = summary
                    }
                }
                await MainActor.run {
                    self.availableParents = parents
                }
            }
        } catch {
            Logger.shared.error("Error fetching \(parentType.lowercased())s: \(error)")
        }

        isLoading = false
    }

    private func updateParent(to parentKey: String?) {
        Task {
            let fields: [String: Any]
            if let parentKey = parentKey {
                // Set new parent using the parent field
                fields = ["parent": ["key": parentKey]]
            } else {
                // Clear parent
                fields = ["parent": NSNull()]
            }

            let success = await jiraService.updateIssue(
                issueKey: issue.key,
                fields: fields
            )

            if success {
                Logger.shared.info("Updated parent for \(issue.key) to \(parentKey ?? "None")")
                await MainActor.run {
                    refreshIssueDetails()
                }
            } else {
                Logger.shared.error("Failed to update parent for \(issue.key)")
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
