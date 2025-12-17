import SwiftUI

struct IndigoView: View {
    @StateObject var viewModel: IndigoViewModel
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.textSizeMultiplier) var textSizeMultiplier
    @Environment(\.openWindow) private var openWindow

    // Computed property for selected issues
    private var selectedIssues: [JiraIssue] {
        jiraService.selectedIssues.compactMap { selectedID in
            jiraService.issues.first { $0.id == selectedID }
        }
    }

    var body: some View {
        ZStack {
            // Background with vibrancy
            VisualEffectView()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Main chat interface
                VStack(spacing: 0) {
                    // Header
                    headerView

                    Divider()

                    // Conversation area
                    conversationView

                    Divider()

                    // Input area
                    inputView
                }

                // Selected issues drawer (slides in from right when issues are selected)
                if !selectedIssues.isEmpty {
                    selectedIssuesDrawer
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selectedIssues.count)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenIssueDetail"))) { notification in
            if let issueKey = notification.userInfo?["issueKey"] as? String {
                openWindow(value: issueKey)
            }
        }
        .onAppear {
            // Apply initial window floating state
            viewModel.setWindowFloating(viewModel.keepOnTop)
        }
    }

    private var headerView: some View {
        HStack {
            // Indigo branding
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.46, green: 0.39, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Indigo")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)

                    Text("AI Assistant for Jira")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 12) {
                // Keep on Top toggle
                Toggle("Keep on Top", isOn: Binding(
                    get: { viewModel.keepOnTop },
                    set: { newValue in
                        viewModel.keepOnTop = newValue
                        viewModel.setWindowFloating(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                // Refresh main window
                Button(action: { viewModel.refreshMainWindow() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh main window")

                // Clear history
                Button(action: { viewModel.clearHistory() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.46, green: 0.39, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 60)

                        Text("Start a conversation")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Ask me to search, update, or create Jira issues")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
            }
            .onChange(of: viewModel.messages.count) { _ in
                // Auto-scroll to latest message
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 0) {
            // Model Selector Row
            HStack {
                Menu {
                    ForEach(AIModel.allCases) { model in
                        Button(action: {
                            viewModel.changeModel(model)
                        }) {
                            HStack {
                                Text(model.displayName)
                                if viewModel.selectedModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))
                        Text(viewModel.selectedModel.displayName)
                            .font(.system(size: 11))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .help("Select AI model")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Input Row
            HStack(spacing: 12) {
                // Microphone button
                Button(action: { viewModel.toggleRecording() }) {
                    Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.isRecording ? .red : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            Group {
                                if viewModel.isRecording {
                                    Color.red.opacity(0.2)
                                } else {
                                    LinearGradient(
                                        colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.46, green: 0.39, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                }
                            }
                        )
                        .cornerRadius(18)
                }
                .buttonStyle(.plain)
                .help("Voice input (Phase 2)")

                // Text input - using custom NSTextField for reliable Enter key handling
                SubmittableTextField(
                    "Type or speak your command...",
                    text: $viewModel.inputText,
                    onSubmit: {
                        viewModel.sendMessage()
                    },
                    font: .systemFont(ofSize: NSFont.systemFontSize),
                    backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.5),
                    focusOnAppear: true
                )
                .frame(height: 36)
                .cornerRadius(8)

                // Send button
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            viewModel.inputText.isEmpty
                                ? LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(
                                    colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.46, green: 0.39, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.isEmpty || viewModel.isProcessing)
                .help("Send message (⏎)")
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    private var selectedIssuesDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drawer header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Issues")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(selectedIssues.count) \(selectedIssues.count == 1 ? "issue" : "issues")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))

            Divider()

            // List of selected issues
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedIssues) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            // Issue key
                            Text(issue.key)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.blue)

                            // Issue summary
                            Text(issue.summary)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            // Metadata
                            HStack(spacing: 8) {
                                // Status badge
                                Text(issue.status)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(statusColor(for: issue.status).opacity(0.2))
                                    .foregroundColor(statusColor(for: issue.status))
                                    .cornerRadius(4)

                                // Assignee
                                if let assignee = issue.assignee {
                                    Text(assignee)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .leading
        )
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
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.sender == .user {
                Spacer()
            }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // Header with sender and timestamp
                HStack(spacing: 6) {
                    senderIcon
                    Text(senderName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(timeString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Message content
                Text(message.text)
                    .textSelection(.enabled)
                    .font(.body)
                    .padding(12)
                    .background(bubbleBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(bubbleBorderColor, lineWidth: 1)
                    )

                // Status indicator if present
                if let status = message.status {
                    HStack(spacing: 4) {
                        statusIcon(for: status)
                        Text(statusText(for: status))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: 400, alignment: message.sender == .user ? .trailing : .leading)

            if message.sender != .user {
                Spacer()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var senderIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 11))
            .foregroundColor(iconColor)
    }

    private var senderName: String {
        switch message.sender {
        case .user: return "You"
        case .ai: return "Indigo"
        case .system: return "System"
        }
    }

    private var iconName: String {
        switch message.sender {
        case .user: return "person.circle.fill"
        case .ai: return "sparkles"
        case .system: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch message.sender {
        case .user: return Color(red: 0.31, green: 0.27, blue: 0.90)
        case .ai: return Color(red: 0.46, green: 0.39, blue: 1.0)
        case .system: return .secondary
        }
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.sender {
        case .user:
            return LinearGradient(
                colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.46, green: 0.39, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ai:
            return LinearGradient(
                colors: [Color(NSColor.controlBackgroundColor).opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .system:
            return LinearGradient(
                colors: [Color.secondary.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var bubbleBorderColor: Color {
        switch message.sender {
        case .user: return .clear
        case .ai: return Color.secondary.opacity(0.2)
        case .system: return Color.secondary.opacity(0.2)
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    private func statusIcon(for status: Message.MessageStatus) -> some View {
        let iconName: String
        let color: Color

        switch status {
        case .success:
            iconName = "checkmark.circle.fill"
            color = .green
        case .warning:
            iconName = "exclamationmark.triangle.fill"
            color = .orange
        case .error:
            iconName = "xmark.circle.fill"
            color = .red
        case .processing:
            iconName = "clock.fill"
            color = .blue
        }

        return Image(systemName: iconName)
            .font(.system(size: 10))
            .foregroundColor(color)
    }

    private func statusText(for status: Message.MessageStatus) -> String {
        switch status {
        case .success: return "Success"
        case .warning: return "Warning"
        case .error: return "Error"
        case .processing: return "Processing..."
        }
    }
}
