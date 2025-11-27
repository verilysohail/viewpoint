import Foundation
import SwiftUI
import Combine

@MainActor
class IndigoViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var keepOnTop: Bool = true
    @Published var modelStatus: String = ""
    @Published var selectedModel: AIModel

    private let jiraService: JiraService
    private var cancellables = Set<AnyCancellable>()
    private var audioRecorder: AudioRecorder?
    private var whisperService: WhisperService?
    private var aiService: AIService?
    private var isWhisperLoaded = false

    init(jiraService: JiraService) {
        self.jiraService = jiraService

        // Load selected model from UserDefaults
        let modelRaw = UserDefaults.standard.string(forKey: "selectedAIModel") ?? AIModel.gemini3ProPreview.rawValue
        self.selectedModel = AIModel(rawValue: modelRaw) ?? .gemini3ProPreview

        // Initialize services
        self.whisperService = WhisperService()
        self.audioRecorder = AudioRecorder()
        self.aiService = AIService(jiraService: jiraService)

        // Add welcome message
        addMessage(Message(
            text: "👋 Hi! I'm Indigo, your AI assistant for Jira. Ask me to search for issues, update them, or create new ones using natural language.",
            sender: .system
        ))

        // Load Whisper model in background
        loadWhisperModel()
    }

    func changeModel(_ newModel: AIModel) {
        selectedModel = newModel

        // Save to UserDefaults
        UserDefaults.standard.set(newModel.rawValue, forKey: "selectedAIModel")

        // Reconfigure AI service
        aiService = AIService(jiraService: jiraService)

        addMessage(Message(
            text: "✓ Switched to \(newModel.displayName)",
            sender: .system,
            status: .success
        ))
    }

    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard let aiService = aiService else {
            addMessage(Message(
                text: "AI Service not configured. Please configure Vertex AI in Settings → AI.",
                sender: .system,
                status: .error
            ))
            return
        }

        let userMessage = Message(
            text: inputText,
            sender: .user
        )

        addMessage(userMessage)

        let messageText = inputText
        inputText = ""
        isProcessing = true

        // Create a placeholder message that will be updated with streamed content
        var aiResponseText = ""
        let aiMessageId = UUID()

        aiService.sendMessage(
            userMessage: messageText,
            conversationHistory: messages,
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    guard let self = self else { return }
                    aiResponseText += chunk

                    // Update or add AI message
                    if let index = self.messages.firstIndex(where: { $0.id == aiMessageId }) {
                        self.messages[index] = Message(
                            id: aiMessageId,
                            text: aiResponseText,
                            sender: .ai,
                            status: .processing
                        )
                    } else {
                        self.addMessage(Message(
                            id: aiMessageId,
                            text: aiResponseText,
                            sender: .ai,
                            status: .processing
                        ))
                    }
                }
            },
            onComplete: { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isProcessing = false

                    switch result {
                    case .success(let response):
                        // Update final message
                        if let index = self.messages.firstIndex(where: { $0.id == aiMessageId }) {
                            self.messages[index] = Message(
                                id: aiMessageId,
                                text: response.text,
                                sender: .ai,
                                status: .success
                            )
                        }

                        // Execute any Jira operations from the intents
                        for intent in response.intents {
                            self.executeIntent(intent)
                        }

                    case .failure(let error):
                        self.addMessage(Message(
                            text: "Error: \(error.localizedDescription)",
                            sender: .system,
                            status: .error
                        ))

                        // Remove the placeholder message
                        if let index = self.messages.firstIndex(where: { $0.id == aiMessageId }) {
                            self.messages.remove(at: index)
                        }
                    }
                }
            }
        )
    }

    private func executeIntent(_ intent: AIResponse.Intent) {
        switch intent {
        case .search(let jql):
            addMessage(Message(
                text: "🔍 Executing search with JQL: \(jql)",
                sender: .system
            ))
            Task {
                await jiraService.searchWithJQL(jql)
                // Check if search was successful
                let issueCount = await MainActor.run { jiraService.issues.count }
                if issueCount > 0 {
                    addMessage(Message(
                        text: "✓ Found \(issueCount) issue\(issueCount == 1 ? "" : "s"). Results are now displayed in the main window.",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "No issues found matching this search.",
                        sender: .system,
                        status: .warning
                    ))
                }
            }

        case .update(let issueKey, let fields):
            addMessage(Message(
                text: "✏️ Updating issue \(issueKey): \(fields)",
                sender: .system
            ))
            Task {
                let success = await jiraService.updateIssue(issueKey: issueKey, fields: fields)
                if success {
                    addMessage(Message(
                        text: "✓ Successfully updated \(issueKey)!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to update issue. Check the logs for details.",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .create(let fields):
            addMessage(Message(
                text: "➕ Creating new issue: \(fields)",
                sender: .system
            ))
            Task {
                let result = await jiraService.createIssue(fields: fields)
                if result.success {
                    if let issueKey = result.issueKey {
                        addMessage(Message(
                            text: "✓ Successfully created issue \(issueKey)!",
                            sender: .system,
                            status: .success
                        ))
                    } else {
                        addMessage(Message(
                            text: "✓ Issue created successfully!",
                            sender: .system,
                            status: .success
                        ))
                    }
                } else {
                    addMessage(Message(
                        text: "✗ Failed to create issue. Check the logs for details.",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .logWork(let issueKey, let timeSeconds):
            addMessage(Message(
                text: "⏱️ Logging \(timeSeconds)s to \(issueKey)",
                sender: .system
            ))
            Task {
                let success = await jiraService.logWork(issueKey: issueKey, timeSpentSeconds: timeSeconds)
                if success {
                    addMessage(Message(
                        text: "✓ Work logged successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to log work",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .changeStatus(let issueKey, let newStatus):
            addMessage(Message(
                text: "🔄 Changing \(issueKey) status to \(newStatus)",
                sender: .system
            ))
            Task {
                let success = await jiraService.updateIssueStatus(issueKey: issueKey, newStatus: newStatus)
                if success {
                    addMessage(Message(
                        text: "✓ Status updated successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to update status",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .addComment(let issueKey, let comment):
            addMessage(Message(
                text: "💬 Adding comment to \(issueKey)",
                sender: .system
            ))
            Task {
                let success = await jiraService.addComment(issueKey: issueKey, comment: comment)
                if success {
                    addMessage(Message(
                        text: "✓ Comment added successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to add comment",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .deleteIssue(let issueKey):
            addMessage(Message(
                text: "🗑️ Deleting issue \(issueKey)",
                sender: .system
            ))
            Task {
                let success = await jiraService.deleteIssue(issueKey: issueKey)
                if success {
                    addMessage(Message(
                        text: "✓ Issue deleted successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to delete issue",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .assignIssue(let issueKey, let assignee):
            addMessage(Message(
                text: "👤 Assigning \(issueKey) to \(assignee)",
                sender: .system
            ))
            Task {
                let success = await jiraService.assignIssue(issueKey: issueKey, assigneeEmail: assignee)
                if success {
                    addMessage(Message(
                        text: "✓ Issue assigned successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to assign issue",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .addWatcher(let issueKey, let watcher):
            addMessage(Message(
                text: "👁️ Adding \(watcher) as watcher to \(issueKey)",
                sender: .system
            ))
            Task {
                let success = await jiraService.addWatcher(issueKey: issueKey, watcherEmail: watcher)
                if success {
                    addMessage(Message(
                        text: "✓ Watcher added successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to add watcher",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .linkIssues(let issueKey, let linkedIssue, let linkType):
            addMessage(Message(
                text: "🔗 Linking \(issueKey) to \(linkedIssue) (\(linkType))",
                sender: .system
            ))
            Task {
                let success = await jiraService.linkIssues(issueKey: issueKey, linkedIssueKey: linkedIssue, linkType: linkType)
                if success {
                    addMessage(Message(
                        text: "✓ Issues linked successfully!",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to link issues",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .fetchChangelog(let issueKey):
            addMessage(Message(
                text: "📜 Fetching change history for \(issueKey)...",
                sender: .system
            ))
            Task {
                let result = await jiraService.fetchChangelog(issueKey: issueKey)
                if result.success, let changelog = result.changelog {
                    addMessage(Message(
                        text: changelog,
                        sender: .ai,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✗ Failed to fetch changelog for \(issueKey)",
                        sender: .system,
                        status: .error
                    ))
                }
            }

        case .showIssueDetail(let issueKey):
            addMessage(Message(
                text: "🔍 Opening detailed view for \(issueKey)...",
                sender: .system
            ))

            // Open the detail window on the main thread
            Task { @MainActor in
                // Use NSWorkspace to open a new window with the issue key
                // This will trigger the WindowGroup(for: String.self) in ViewpointApp
                if #available(macOS 13.0, *) {
                    // On macOS 13+, we can use the openWindow environment action
                    // But since we're in a ViewModel, we'll use a different approach
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenIssueDetail"),
                        object: nil,
                        userInfo: ["issueKey": issueKey]
                    )
                }

                addMessage(Message(
                    text: "✓ Detail window opened for \(issueKey)",
                    sender: .system,
                    status: .success
                ))
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            // Stop recording and transcribe
            stopRecording()
        } else {
            // Start recording
            startRecording()
        }
    }

    private func loadWhisperModel() {
        guard let whisperService = whisperService else { return }

        addMessage(Message(
            text: "Loading Whisper model for voice transcription...",
            sender: .system
        ))

        whisperService.loadModel(
            onProgress: { [weak self] status in
                Task { @MainActor in
                    self?.modelStatus = status
                }
            },
            completion: { [weak self] success in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isWhisperLoaded = success
                    if success {
                        self.addMessage(Message(
                            text: "✓ Voice transcription ready! Click the microphone to record.",
                            sender: .system
                        ))
                    } else {
                        self.addMessage(Message(
                            text: "⚠️ Voice transcription unavailable. You can still type messages.",
                            sender: .system,
                            status: .warning
                        ))
                    }
                }
            }
        )
    }

    private func startRecording() {
        guard isWhisperLoaded else {
            addMessage(Message(
                text: "Voice transcription is still loading. Please wait...",
                sender: .system,
                status: .warning
            ))
            return
        }

        guard let audioRecorder = audioRecorder else { return }

        // Request microphone permission first
        audioRecorder.requestPermission { [weak self] granted in
            Task { @MainActor in
                guard let self = self else { return }

                if granted {
                    if audioRecorder.startRecording() {
                        self.isRecording = true
                        self.addMessage(Message(
                            text: "🎤 Recording... Click mic again to stop and transcribe.",
                            sender: .system
                        ))
                    } else {
                        self.addMessage(Message(
                            text: "Failed to start recording. Please try again.",
                            sender: .system,
                            status: .error
                        ))
                    }
                } else {
                    self.addMessage(Message(
                        text: "Microphone permission denied. Please enable it in System Settings → Privacy & Security → Microphone, then restart Viewpoint.",
                        sender: .system,
                        status: .error
                    ))
                    // Open System Settings to help user enable permission
                    audioRecorder.openSystemSettings()
                }
            }
        }
    }

    private func stopRecording() {
        guard let audioRecorder = audioRecorder,
              let whisperService = whisperService else { return }

        isRecording = false

        guard let audioData = audioRecorder.stopRecording() else {
            addMessage(Message(
                text: "Failed to stop recording.",
                sender: .system,
                status: .error
            ))
            return
        }

        // Show processing message
        addMessage(Message(
            text: "🔄 Transcribing audio...",
            sender: .system,
            status: .processing
        ))

        // Transcribe the audio
        whisperService.transcribe(audioData: audioData) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let transcription):
                    if transcription.isEmpty {
                        self.addMessage(Message(
                            text: "No speech detected. Please try again.",
                            sender: .system,
                            status: .warning
                        ))
                    } else {
                        // Fill the text input with the transcription
                        self.inputText = transcription
                        self.addMessage(Message(
                            text: "✓ Transcribed: \"\(transcription)\"",
                            sender: .system,
                            status: .success
                        ))
                    }

                case .failure(let error):
                    self.addMessage(Message(
                        text: "Transcription failed: \(error.localizedDescription)",
                        sender: .system,
                        status: .error
                    ))
                }
            }
        }
    }

    func addMessage(_ message: Message) {
        messages.append(message)
    }

    func clearHistory() {
        messages.removeAll()
        addMessage(Message(
            text: "Conversation cleared.",
            sender: .system
        ))
    }

    func refreshMainWindow() {
        addMessage(Message(
            text: "🔄 Refreshing main window...",
            sender: .system
        ))
        Task {
            await jiraService.fetchMyIssues()
            addMessage(Message(
                text: "✓ Main window refreshed!",
                sender: .system,
                status: .success
            ))
        }
    }

    func setWindowFloating(_ floating: Bool) {
        // Get the Indigo window
        for window in NSApplication.shared.windows {
            if window.title == "Indigo" {
                window.level = floating ? .floating : .normal
                break
            }
        }
    }
}
