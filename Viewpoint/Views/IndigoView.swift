import SwiftUI

struct IndigoView: View {
    @StateObject var viewModel: IndigoViewModel
    @Environment(\.textSizeMultiplier) var textSizeMultiplier

    var body: some View {
        ZStack {
            // Background with vibrancy
            VisualEffectView()
                .ignoresSafeArea()

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

            // Text input
            TextField("Type or speak your command...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .onSubmit {
                    viewModel.sendMessage()
                }

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
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
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
