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

    // Pending options for multi-turn selection
    private var pendingClassificationOptions: [(display: String, parentValue: String, childValue: String?)] = []
    private var pendingClassificationIssueKey: String?
    private var pendingPCMOptions: [(display: String, id: String, objectKey: String)] = []
    private var pendingPCMIssueKey: String?

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

                        // Execute actions or intents
                        if !response.actions.isEmpty {
                            // New: Execute JSON-based actions via CapabilityRegistry
                            Logger.shared.info("Executing \(response.actions.count) actions via CapabilityRegistry")
                            Task {
                                for action in response.actions {
                                    Logger.shared.info("Executing action: \(action.tool)")
                                    await self.executeAction(action)
                                }
                            }
                        } else if !response.intents.isEmpty {
                            // Legacy: Execute parsed intents
                            Logger.shared.info("Executing \(response.intents.count) legacy intents")
                            Task {
                                for intent in response.intents {
                                    Logger.shared.info("Executing intent: \(intent)")
                                    await self.executeIntent(intent)
                                }
                            }
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

    // MARK: - Action Execution (New JSON-based system)

    private func executeAction(_ action: AIAction) async {
        Logger.shared.info("Executing action: \(action.tool) with args: \(action.arguments)")

        // Show executing message
        addMessage(Message(
            text: "⚡ Executing: \(action.tool)",
            sender: .system,
            status: .processing
        ))

        do {
            let result = try await CapabilityRegistry.shared.execute(
                toolName: action.tool,
                arguments: action.arguments
            )

            if result.success {
                // Special handling for search results - update the main window
                if action.tool == "search_issues" {
                    let issueCount = jiraService.issues.count
                    if issueCount > 0 {
                        addMessage(Message(
                            text: "✓ Found \(issueCount) issue\(issueCount == 1 ? "" : "s"). Results displayed in main window.",
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
                } else if let message = result.message {
                    addMessage(Message(
                        text: "✓ \(message)",
                        sender: .system,
                        status: .success
                    ))
                } else {
                    addMessage(Message(
                        text: "✓ \(action.tool) completed successfully",
                        sender: .system,
                        status: .success
                    ))
                }

                // If data was returned, we could display it here
                if let data = result.data {
                    Logger.shared.debug("Action \(action.tool) returned data: \(data)")
                }
            } else {
                addMessage(Message(
                    text: "✗ \(result.message ?? "Action failed")",
                    sender: .system,
                    status: .error
                ))
            }
        } catch {
            Logger.shared.error("Action execution error: \(error)")
            addMessage(Message(
                text: "✗ Error: \(error.localizedDescription)",
                sender: .system,
                status: .error
            ))
        }
    }

    // MARK: - Intent Execution (Legacy system)

    private func executeIntent(_ intent: AIResponse.Intent) async {
        switch intent {
        case .search(let jql):
            addMessage(Message(
                text: "🔍 Executing search with JQL: \(jql)",
                sender: .system
            ))
            await jiraService.searchWithJQL(jql)
            // Check if search was successful
            let issueCount = jiraService.issues.count
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

        case .update(let issueKey, let fields):
            addMessage(Message(
                text: "✏️ Updating issue \(issueKey): \(fields)",
                sender: .system
            ))

            // Validate and map fields using AI (same pattern as CREATE)
            var fieldsToUse = fields
            if let aiService = aiService {
                addMessage(Message(
                    text: "🔍 Validating field values...",
                    sender: .system
                ))

                let (mappedFields, clarification) = await aiService.validateUpdateFields(
                    issueKey: issueKey,
                    userFields: fields
                )

                if let clarification = clarification {
                    addMessage(Message(
                        text: "❓ \(clarification)",
                        sender: .system,
                        status: .warning
                    ))
                    return
                }

                if let mapped = mappedFields {
                    fieldsToUse = mapped
                    Logger.shared.info("Using validated fields: \(fieldsToUse)")
                }
            }

            let success = await jiraService.updateIssue(issueKey: issueKey, fields: fieldsToUse)
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

        case .create(let fields):
            addMessage(Message(
                text: "➕ Creating new issue: \(fields)",
                sender: .system
            ))

            // Extract project key and issue type for validation
            guard let projectKey = fields["project"] as? String else {
                addMessage(Message(
                    text: "✗ Missing required field: project",
                    sender: .system,
                    status: .error
                ))
                return
            }

            let issueType = (fields["type"] as? String) ?? "Story"

            // Check if user requested "current" sprint - if so, resolve ambiguity first
            var fieldsToValidate = fields
            if let sprintValue = fields["sprint"] as? String,
               sprintValue.lowercased() == "current" {

                // Find all active sprints for this project
                let activeSprints = await jiraService.findActiveSprintsForProject(projectKey: projectKey)

                if activeSprints.count > 1 {
                    // Multiple active sprints - ask user which one
                    let sprintList = activeSprints.map { "\($0.name) (ID: \($0.id))" }.joined(separator: ", ")
                    addMessage(Message(
                        text: "❓ I found \(activeSprints.count) active sprints for \(projectKey): \(sprintList). Please specify which sprint you want to use.",
                        sender: .system,
                        status: .error
                    ))
                    return
                } else if activeSprints.count == 1 {
                    // Exactly one sprint - use it
                    addMessage(Message(
                        text: "✓ Found active sprint: \(activeSprints[0].name)",
                        sender: .system
                    ))
                } else {
                    // No active sprints found
                    addMessage(Message(
                        text: "⚠️ No active sprint found for \(projectKey). Creating issue without sprint assignment.",
                        sender: .system,
                        status: .error
                    ))
                    // Remove sprint from fields
                    var mutableFields = fields
                    mutableFields.removeValue(forKey: "sprint")
                    fieldsToValidate = mutableFields
                }
            }

            // Validate and map fields using AI
            if let aiService = aiService {
                addMessage(Message(
                    text: "🔍 Validating fields against Jira schema...",
                    sender: .system
                ))

                let (mappedFields, clarification) = await aiService.validateAndMapFields(
                    userFields: fieldsToValidate,
                    projectKey: projectKey,
                    issueType: issueType
                )

                // Check if clarification is needed
                if let clarification = clarification {
                    addMessage(Message(
                        text: "❓ \(clarification)",
                        sender: .system,
                        status: .error
                    ))
                    return
                }

                // Use mapped fields if available, otherwise fall back to original
                let fieldsToUse = mappedFields ?? fieldsToValidate

                addMessage(Message(
                    text: "✅ Fields validated. Creating issue...",
                    sender: .system
                ))

                let result = await jiraService.createIssue(fields: fieldsToUse)
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
            } else {
                // Fallback: create without validation if AI service not available
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

        case .changeStatus(let issueKey, let newStatus):
            addMessage(Message(
                text: "🔄 Changing \(issueKey) status to \(newStatus)",
                sender: .system
            ))
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

        case .addComment(let issueKey, let comment):
            addMessage(Message(
                text: "💬 Adding comment to \(issueKey)",
                sender: .system
            ))
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

        case .deleteIssue(let issueKey):
            addMessage(Message(
                text: "🗑️ Deleting issue \(issueKey)",
                sender: .system
            ))
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

        case .assignIssue(let issueKey, let assignee):
            addMessage(Message(
                text: "👤 Assigning \(issueKey) to \(assignee)",
                sender: .system
            ))
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

        case .addWatcher(let issueKey, let watcher):
            addMessage(Message(
                text: "👁️ Adding \(watcher) as watcher to \(issueKey)",
                sender: .system
            ))
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

        case .linkIssues(let issueKey, let linkedIssue, let linkType):
            addMessage(Message(
                text: "🔗 Linking \(issueKey) to \(linkedIssue) (\(linkType))",
                sender: .system
            ))
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

        case .fetchChangelog(let issueKey):
            addMessage(Message(
                text: "📜 Fetching change history for \(issueKey)...",
                sender: .system
            ))
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

        case .showIssueDetail(let issueKey):
            addMessage(Message(
                text: "🔍 Opening detailed view for \(issueKey)...",
                sender: .system
            ))

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

        case .getTransitions(let issueKey):
            addMessage(Message(
                text: "🔄 Fetching available transitions and resolutions for \(issueKey)...",
                sender: .system
            ))

            Logger.shared.info("GET_TRANSITIONS: Starting fetch for \(issueKey)")
            // Fetch transitions for the issue (with field information)
            guard let url = URL(string: "\(jiraService.config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/transitions?expand=transitions.fields") else {
                Logger.shared.error("GET_TRANSITIONS: Invalid URL")
                addMessage(Message(
                    text: "❌ Invalid URL for transitions",
                    sender: .system,
                    status: .error
                ))
                return
            }

            Logger.shared.info("GET_TRANSITIONS: Fetching from URL: \(url)")
            do {
                let request = jiraService.createRequest(url: url)
                Logger.shared.info("GET_TRANSITIONS: Request created, fetching...")
                let (data, _) = try await URLSession.shared.data(for: request)
                Logger.shared.info("GET_TRANSITIONS: Received \(data.count) bytes")

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let transitions = json["transitions"] as? [[String: Any]] {

                    Logger.shared.info("GET_TRANSITIONS: Parsed JSON, found \(transitions.count) transitions")
                    var transitionInfo: [String] = []

                    for (index, trans) in transitions.enumerated() {
                        Logger.shared.info("GET_TRANSITIONS: Processing transition \(index + 1)")
                        Logger.shared.info("GET_TRANSITIONS: Transition keys: \(trans.keys.joined(separator: ", "))")

                        if let transitionName = trans["name"] as? String,
                           let to = trans["to"] as? [String: Any],
                           let toStatus = to["name"] as? String {

                            Logger.shared.info("GET_TRANSITIONS: Found transition '\(transitionName)' -> '\(toStatus)'")

                            var info = "Transition '\(transitionName)' → Status '\(toStatus)'"

                            // Check for required fields (like resolution)
                            if let fields = trans["fields"] as? [String: Any] {
                                var requiredFields: [String] = []
                                for (fieldKey, fieldValue) in fields {
                                    if let fieldDict = fieldValue as? [String: Any],
                                       let required = fieldDict["required"] as? Bool,
                                       required,
                                       let fieldName = fieldDict["name"] as? String {

                                        if let allowedValues = fieldDict["allowedValues"] as? [[String: Any]] {
                                            let values = allowedValues.compactMap { $0["name"] as? String }
                                            if !values.isEmpty {
                                                requiredFields.append("\(fieldName): [\(values.joined(separator: ", "))]")
                                            }
                                        } else {
                                            requiredFields.append(fieldName)
                                        }
                                    }
                                }
                                if !requiredFields.isEmpty {
                                    info += "\n    Required: \(requiredFields.joined(separator: ", "))"
                                }
                            }

                            transitionInfo.append(info)
                            Logger.shared.info("GET_TRANSITIONS: Added transition info: \(info)")
                        } else {
                            Logger.shared.error("GET_TRANSITIONS: Failed to parse transition \(index + 1)")
                        }
                    }

                    Logger.shared.info("GET_TRANSITIONS: Collected \(transitionInfo.count) transition infos")
                    let message = "Available transitions for \(issueKey):\n\n" + transitionInfo.joined(separator: "\n\n")
                    Logger.shared.info("GET_TRANSITIONS: Final message length: \(message.count) chars")
                    Logger.shared.info("GET_TRANSITIONS: About to call addMessage")

                    addMessage(Message(
                        text: message,
                        sender: .system,
                        status: .success
                    ))
                    Logger.shared.info("GET_TRANSITIONS: addMessage completed")
                } else {
                    Logger.shared.error("GET_TRANSITIONS: Failed to parse JSON response")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        Logger.shared.error("GET_TRANSITIONS: Response was: \(jsonString)")
                    }
                    addMessage(Message(
                        text: "❌ Could not parse transitions for \(issueKey)",
                        sender: .system,
                        status: .error
                    ))
                }
            } catch {
                Logger.shared.error("GET_TRANSITIONS: Error - \(error.localizedDescription)")
                addMessage(Message(
                    text: "❌ Failed to fetch transitions for \(issueKey): \(error.localizedDescription)",
                    sender: .system,
                    status: .error
                ))
            }

        case .sprintLookup(let query, let projectKey):
            addMessage(Message(
                text: "🔍 Looking up sprint information: \(query)",
                sender: .system
            ))

            // Get available sprints from JiraService
            let sprints = await MainActor.run { jiraService.availableSprints }

            // Filter by project if specified
            let searchSprints = sprints
            if let projectKey = projectKey {
                // Filter sprints that might be associated with the project
                // Note: Sprints don't have direct project association in the model,
                // but we can filter based on active project context
                Logger.shared.info("SPRINT_LOOKUP: Filtering for project \(projectKey)")
            }

            // Search for matching sprints based on query
            let queryLower = query.lowercased()
            var matchingSprints: [JiraSprint] = []

            // Check for specific sprint name or ID in query
            for sprint in searchSprints {
                let nameLower = sprint.name.lowercased()

                // Match by name
                if nameLower.contains(queryLower) || queryLower.contains(nameLower) {
                    matchingSprints.append(sprint)
                    continue
                }

                // Match by ID if query contains a number
                if queryLower.contains("\(sprint.id)") {
                    matchingSprints.append(sprint)
                    continue
                }

                // Match by state (active, future, closed)
                if queryLower.contains("active") && sprint.state.lowercased() == "active" {
                    matchingSprints.append(sprint)
                    continue
                }
                if queryLower.contains("future") && sprint.state.lowercased() == "future" {
                    matchingSprints.append(sprint)
                    continue
                }
                if queryLower.contains("closed") && sprint.state.lowercased() == "closed" {
                    matchingSprints.append(sprint)
                    continue
                }
                if queryLower.contains("current") && sprint.state.lowercased() == "active" {
                    matchingSprints.append(sprint)
                    continue
                }

                // Match by date if sprint has dates
                if let startDate = sprint.startDate, let endDate = sprint.endDate {
                    // Simple date matching - check if query mentions dates that overlap with sprint
                    // Look for month names in query
                    let months = ["january", "february", "march", "april", "may", "june",
                                  "july", "august", "september", "october", "november", "december"]
                    for (index, month) in months.enumerated() {
                        if queryLower.contains(month) {
                            let monthNum = index + 1
                            let monthStr = String(format: "%02d", monthNum)
                            // Check if sprint dates include this month
                            if startDate.contains("-\(monthStr)-") || endDate.contains("-\(monthStr)-") {
                                matchingSprints.append(sprint)
                                break
                            }
                        }
                    }
                }
            }

            // Remove duplicates
            let uniqueSprints = Array(Set(matchingSprints.map { $0.id })).compactMap { id in
                matchingSprints.first { $0.id == id }
            }

            if uniqueSprints.isEmpty {
                // If no matches found, show all available sprints
                if searchSprints.isEmpty {
                    addMessage(Message(
                        text: "📋 No sprints found in the current context. Try selecting a project first.",
                        sender: .system,
                        status: .warning
                    ))
                } else {
                    var message = "📋 No sprints matching '\(query)' found. Here are all available sprints:\n\n"
                    for sprint in searchSprints.prefix(10) {
                        message += "• **\(sprint.name)** (ID: \(sprint.id))\n"
                        message += "  State: \(sprint.state)"
                        if let start = sprint.startDate, let end = sprint.endDate {
                            message += " | \(start) to \(end)"
                        }
                        message += "\n"
                    }
                    if searchSprints.count > 10 {
                        message += "\n...and \(searchSprints.count - 10) more sprints"
                    }
                    addMessage(Message(
                        text: message,
                        sender: .system,
                        status: .success
                    ))
                }
            } else {
                var message = "📋 Found \(uniqueSprints.count) sprint(s) matching '\(query)':\n\n"
                for sprint in uniqueSprints {
                    message += "• **\(sprint.name)** (ID: \(sprint.id))\n"
                    message += "  State: \(sprint.state)"
                    if let start = sprint.startDate, let end = sprint.endDate {
                        message += " | \(start) to \(end)"
                    }
                    if let goal = sprint.goal, !goal.isEmpty {
                        message += "\n  Goal: \(goal)"
                    }
                    message += "\n"
                }
                addMessage(Message(
                    text: message,
                    sender: .system,
                    status: .success
                ))
            }

        case .componentLookup(let projectKey):
            addMessage(Message(
                text: "🔍 Looking up components for project \(projectKey)...",
                sender: .system
            ))

            let result = await jiraService.fetchProjectComponents(projectKey: projectKey)

            if result.success {
                if result.components.isEmpty {
                    addMessage(Message(
                        text: "📋 No components found for project \(projectKey).",
                        sender: .system,
                        status: .warning
                    ))
                } else {
                    var message = "📋 Components for project \(projectKey) (\(result.components.count) total):\n\n"
                    for component in result.components {
                        message += "• **\(component.name)**"
                        if let description = component.description, !description.isEmpty {
                            message += "\n  \(description)"
                        }
                        if let lead = component.lead, let leadName = lead.displayName {
                            message += "\n  Lead: \(leadName)"
                        }
                        message += "\n"
                    }
                    addMessage(Message(
                        text: message,
                        sender: .system,
                        status: .success
                    ))
                }
            } else {
                addMessage(Message(
                    text: "❌ Failed to fetch components for project \(projectKey). Make sure the project key is correct.",
                    sender: .system,
                    status: .error
                ))
            }

        case .classificationLookup(let issueKey, let query):
            addMessage(Message(
                text: "🔍 Searching Request Classification options for \"\(query)\"...",
                sender: .system
            ))

            let results = await jiraService.searchRequestClassificationOptions(query: query)

            if results.isEmpty {
                addMessage(Message(
                    text: "No classification options found matching \"\(query)\". Try a different search term.",
                    sender: .system,
                    status: .warning
                ))
            } else {
                // Store pending options for selection
                pendingClassificationOptions = Array(results.prefix(5))
                pendingClassificationIssueKey = issueKey

                var message = "📋 Found \(results.count) matching classification options for \(issueKey):\n\n"
                for (index, option) in pendingClassificationOptions.enumerated() {
                    message += "**\(index + 1).** \(option.display)\n"
                }
                message += "\nReply with a number (1-\(pendingClassificationOptions.count)) to select an option."

                addMessage(Message(
                    text: message,
                    sender: .system,
                    status: .success
                ))
            }

        case .classificationSelect(let issueKey, let optionIndex):
            // Check if we have pending options
            guard !pendingClassificationOptions.isEmpty,
                  let pendingIssueKey = pendingClassificationIssueKey,
                  pendingIssueKey == issueKey || issueKey.isEmpty else {
                addMessage(Message(
                    text: "❌ No pending classification options. Please search first using a query like \"classify this as software\".",
                    sender: .system,
                    status: .error
                ))
                return
            }

            let actualIssueKey = issueKey.isEmpty ? pendingIssueKey : issueKey

            guard optionIndex >= 1 && optionIndex <= pendingClassificationOptions.count else {
                addMessage(Message(
                    text: "❌ Invalid option number. Please choose between 1 and \(pendingClassificationOptions.count).",
                    sender: .system,
                    status: .error
                ))
                return
            }

            let selectedOption = pendingClassificationOptions[optionIndex - 1]
            addMessage(Message(
                text: "✏️ Setting Request Classification to \"\(selectedOption.display)\"...",
                sender: .system
            ))

            let success = await jiraService.updateRequestClassification(
                issueKey: actualIssueKey,
                parentValue: selectedOption.parentValue,
                childValue: selectedOption.childValue
            )

            if success {
                addMessage(Message(
                    text: "✅ Successfully set Request Classification to \"\(selectedOption.display)\" for \(actualIssueKey).",
                    sender: .system,
                    status: .success
                ))
                // Clear pending options
                pendingClassificationOptions = []
                pendingClassificationIssueKey = nil
                // Refresh issues
                Task { await jiraService.fetchMyIssues() }
            } else {
                addMessage(Message(
                    text: "❌ Failed to update Request Classification for \(actualIssueKey).",
                    sender: .system,
                    status: .error
                ))
            }

        case .pcmLookup(let issueKey, let query):
            addMessage(Message(
                text: "🔍 Searching PCM Master options for \"\(query)\"...",
                sender: .system
            ))

            let results = await jiraService.searchPCMMasterOptions(query: query)

            if results.isEmpty {
                addMessage(Message(
                    text: "No PCM Master options found matching \"\(query)\". Try a different search term.",
                    sender: .system,
                    status: .warning
                ))
            } else {
                // Store pending options for selection
                pendingPCMOptions = Array(results.prefix(5))
                pendingPCMIssueKey = issueKey

                var message = "📋 Found \(results.count) matching PCM Master options for \(issueKey):\n\n"
                for (index, option) in pendingPCMOptions.enumerated() {
                    message += "**\(index + 1).** \(option.display)\n"
                }
                message += "\nReply with a number (1-\(pendingPCMOptions.count)) to select an option."

                addMessage(Message(
                    text: message,
                    sender: .system,
                    status: .success
                ))
            }

        case .pcmSelect(let issueKey, let optionIndex):
            // Check if we have pending options
            guard !pendingPCMOptions.isEmpty,
                  let pendingIssueKey = pendingPCMIssueKey,
                  pendingIssueKey == issueKey || issueKey.isEmpty else {
                addMessage(Message(
                    text: "❌ No pending PCM options. Please search first using a query like \"set PCM to Slack\".",
                    sender: .system,
                    status: .error
                ))
                return
            }

            let actualIssueKey = issueKey.isEmpty ? pendingIssueKey : issueKey

            guard optionIndex >= 1 && optionIndex <= pendingPCMOptions.count else {
                addMessage(Message(
                    text: "❌ Invalid option number. Please choose between 1 and \(pendingPCMOptions.count).",
                    sender: .system,
                    status: .error
                ))
                return
            }

            let selectedOption = pendingPCMOptions[optionIndex - 1]
            addMessage(Message(
                text: "✏️ Setting PCM Master to \"\(selectedOption.display)\"...",
                sender: .system
            ))

            let success = await jiraService.updatePCMMaster(issueKey: actualIssueKey, objectId: selectedOption.id)

            if success {
                addMessage(Message(
                    text: "✅ Successfully set PCM Master to \"\(selectedOption.display)\" for \(actualIssueKey).",
                    sender: .system,
                    status: .success
                ))
                // Clear pending options
                pendingPCMOptions = []
                pendingPCMIssueKey = nil
                // Refresh issues
                Task { await jiraService.fetchMyIssues() }
            } else {
                addMessage(Message(
                    text: "❌ Failed to update PCM Master for \(actualIssueKey).",
                    sender: .system,
                    status: .error
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
