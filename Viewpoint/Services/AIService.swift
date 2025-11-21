import Foundation
import SwiftUI

class AIService {
    private var client: VertexAIClient?
    private let jiraService: JiraService

    init(jiraService: JiraService) {
        self.jiraService = jiraService
        configureClient()
    }

    private func configureClient() {
        // Load the selected model
        let modelRaw = UserDefaults.standard.string(forKey: "selectedAIModel") ?? AIModel.gemini3ProPreview.rawValue

        guard let model = AIModel.allCases.first(where: { $0.rawValue == modelRaw }) else {
            Logger.shared.warning("Invalid model selection. Please configure in Settings → AI.")
            return
        }

        // Load model-specific configuration
        let projectID = UserDefaults.standard.string(forKey: "vertexProjectID_\(model.rawValue)") ?? ""
        let region = UserDefaults.standard.string(forKey: "vertexRegion_\(model.rawValue)") ?? "us-central1"

        guard !projectID.isEmpty else {
            Logger.shared.warning("Vertex AI not configured for \(model.displayName). Please configure in Settings → AI.")
            return
        }

        client = VertexAIClient(
            projectID: projectID,
            region: region,
            model: model
        )

        Logger.shared.info("AI Service configured with model: \(model.displayName) using gcloud auth")
    }

    // MARK: - Chat Completion

    func sendMessage(
        userMessage: String,
        conversationHistory: [Message],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) {
        guard let client = client else {
            onComplete(.failure(VertexAIError.missingCredentials))
            return
        }

        // Build conversation context
        let context = buildContext()
        let systemPrompt = buildSystemPrompt(context: context)

        // Convert conversation history to chat messages
        var messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt)
        ]

        // Add conversation history (last 10 messages to keep context manageable)
        let recentHistory = conversationHistory
            .filter { $0.sender == .user || $0.sender == .ai }
            .suffix(10)

        for msg in recentHistory {
            let role: ChatMessage.Role = msg.sender == .user ? .user : .assistant
            messages.append(ChatMessage(role: role, content: msg.text))
        }

        // Add current user message
        messages.append(ChatMessage(role: .user, content: userMessage))

        // Stream response
        var fullResponse = ""

        client.streamCompletion(
            messages: messages,
            onChunk: { chunk in
                fullResponse += chunk
                onChunk(chunk)
            },
            onComplete: { result in
                switch result {
                case .success(let usage):
                    let response = AIResponse(
                        text: fullResponse,
                        intent: self.parseIntent(from: fullResponse),
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens
                    )
                    onComplete(.success(response))

                case .failure(let error):
                    onComplete(.failure(error))
                }
            }
        )
    }

    // MARK: - Context Building

    private func buildContext() -> AIContext {
        let currentUser = UserDefaults.standard.string(forKey: "jiraEmail") ?? "unknown"

        return AIContext(
            currentUser: currentUser,
            selectedIssues: [],
            currentFilters: jiraService.filters,
            visibleIssues: Array(jiraService.issues.prefix(20)), // Top 20 for context
            availableProjects: Array(jiraService.availableProjects),
            availableSprints: jiraService.availableSprints,
            availableEpics: Array(jiraService.availableEpics),
            lastSearchResults: nil,
            lastCreatedIssue: nil
        )
    }

    private func buildSystemPrompt(context: AIContext) -> String {
        return """
        You are Indigo, an AI assistant for Jira integrated into Viewpoint, a macOS Jira client.

        Your role is to help users manage their Jira issues using natural language. You can:
        1. Search for issues using JQL (Jira Query Language)
        2. Update issue fields (status, assignee, estimates, etc.)
        3. Create new issues
        4. Log work on issues
        5. Provide summaries and insights

        CURRENT CONTEXT:
        - Current user: \(context.currentUser)
        - Available projects: \(context.availableProjects.joined(separator: ", "))
        - Active filters: \(describeFilters(context.currentFilters))
        - Visible issues: \(context.visibleIssues.count) issues currently loaded
        - Available sprints: \(context.availableSprints.map { $0.name }.joined(separator: ", "))

        IMPORTANT INSTRUCTIONS:
        You can perform these Jira operations by including special format markers in your response:

        1. SEARCH: Generate JQL queries
           Format: `JQL: <query>`
           Example: JQL: assignee = currentUser() AND sprint in openSprints()

        2. CREATE: Create new issues
           Format: `CREATE: project=X | summary=Y | type=Z | ...`
           Example: CREATE: project=SETI | summary=Fix bug | type=Bug | assignee=\(context.currentUser)

        3. UPDATE: Update issue fields (summary, description, assignee, priority, labels, components, estimates, sprint, epic)
           Format: `UPDATE: <key> | field=value | field2=value2`
           Example: UPDATE: SETI-123 | summary=New title | priority=High | labels=urgent,bug

        4. COMMENT: Add comment to issue
           Format: `COMMENT: <key> | <comment text>`
           Example: COMMENT: SETI-123 | This issue is blocked by SETI-100

        5. LOG WORK: Log time spent
           Format: `LOG: <key> | time=<duration>`
           Example: LOG: SETI-123 | time=2h

        6. ASSIGN: Assign issue to user
           Format: `ASSIGN: <key> | <email>`
           Example: ASSIGN: SETI-123 | \(context.currentUser)

        7. DELETE: Delete an issue
           Format: `DELETE: <key>`
           Example: DELETE: SETI-123

        8. WATCH: Add watcher to issue
           Format: `WATCH: <key> | <email>`
           Example: WATCH: SETI-123 | \(context.currentUser)

        9. LINK: Link two issues
           Format: `LINK: <key> | <linked-key> | <link-type>`
           Link types: Blocks, Relates to, Duplicates, Clones
           Example: LINK: SETI-123 | SETI-124 | Blocks

        IMPORTANT:
        - Always explain what you're doing in plain language alongside the operation
        - You can update multiple fields in one UPDATE command
        - For sprint, use "sprint=current" to assign to active sprint
        - Be concise and helpful
        - Confirm the operation after completion

        Respond naturally and help the user accomplish their Jira tasks efficiently.
        """
    }

    private func describeFilters(_ filters: IssueFilters) -> String {
        var parts: [String] = []

        if !filters.projects.isEmpty {
            parts.append("Projects: \(filters.projects.joined(separator: ", "))")
        }
        if !filters.statuses.isEmpty {
            parts.append("Statuses: \(filters.statuses.joined(separator: ", "))")
        }
        if !filters.assignees.isEmpty {
            parts.append("Assignees: \(filters.assignees.joined(separator: ", "))")
        }

        return parts.isEmpty ? "No active filters" : parts.joined(separator: " | ")
    }

    // MARK: - Intent Parsing

    private func parseIntent(from response: String) -> AIResponse.Intent? {
        // Look for special format markers in the response
        let lines = response.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // JQL Search
            if trimmed.hasPrefix("JQL:") {
                let jql = trimmed.replacingOccurrences(of: "JQL:", with: "").trimmingCharacters(in: .whitespaces)
                return .search(jql: jql)
            }

            // Update
            if trimmed.hasPrefix("UPDATE:") {
                let parts = trimmed.replacingOccurrences(of: "UPDATE:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                var fields: [String: Any] = [:]

                for i in 1..<parts.count {
                    let fieldParts = parts[i].components(separatedBy: "=")
                    if fieldParts.count == 2 {
                        fields[fieldParts[0].trimmingCharacters(in: .whitespaces)] =
                            fieldParts[1].trimmingCharacters(in: .whitespaces)
                    }
                }

                return .update(issueKey: issueKey, fields: fields)
            }

            // Create
            if trimmed.hasPrefix("CREATE:") {
                let parts = trimmed.replacingOccurrences(of: "CREATE:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                var fields: [String: Any] = [:]
                for part in parts {
                    let fieldParts = part.components(separatedBy: "=")
                    if fieldParts.count == 2 {
                        fields[fieldParts[0].trimmingCharacters(in: .whitespaces)] =
                            fieldParts[1].trimmingCharacters(in: .whitespaces)
                    }
                }

                return .create(fields: fields)
            }

            // Log work
            if trimmed.hasPrefix("LOG:") {
                let parts = trimmed.replacingOccurrences(of: "LOG:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]

                // Parse time
                if let timePart = parts.first(where: { $0.hasPrefix("time=") }) {
                    let timeString = timePart.replacingOccurrences(of: "time=", with: "")
                    if let seconds = parseTimeString(timeString) {
                        return .logWork(issueKey: issueKey, timeSeconds: seconds)
                    }
                }
            }

            // Add comment
            if trimmed.hasPrefix("COMMENT:") {
                let parts = trimmed.replacingOccurrences(of: "COMMENT:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                let comment = parts[1]
                return .addComment(issueKey: issueKey, comment: comment)
            }

            // Delete issue
            if trimmed.hasPrefix("DELETE:") {
                let issueKey = trimmed.replacingOccurrences(of: "DELETE:", with: "").trimmingCharacters(in: .whitespaces)
                return .deleteIssue(issueKey: issueKey)
            }

            // Assign issue
            if trimmed.hasPrefix("ASSIGN:") {
                let parts = trimmed.replacingOccurrences(of: "ASSIGN:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                let assignee = parts[1]
                return .assignIssue(issueKey: issueKey, assignee: assignee)
            }

            // Add watcher
            if trimmed.hasPrefix("WATCH:") {
                let parts = trimmed.replacingOccurrences(of: "WATCH:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                let watcher = parts[1]
                return .addWatcher(issueKey: issueKey, watcher: watcher)
            }

            // Link issues
            if trimmed.hasPrefix("LINK:") {
                let parts = trimmed.replacingOccurrences(of: "LINK:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 3 else { continue }
                let issueKey = parts[0]
                let linkedIssue = parts[1]
                let linkType = parts[2]
                return .linkIssues(issueKey: issueKey, linkedIssue: linkedIssue, linkType: linkType)
            }
        }

        return nil
    }

    private func parseTimeString(_ timeString: String) -> Int? {
        let trimmed = timeString.trimmingCharacters(in: .whitespaces).lowercased()

        // Extract number and unit
        let components = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
        let numberString = components.joined()

        guard let value = Int(numberString) else { return nil }

        if trimmed.contains("d") {
            return value * 8 * 3600 // days (8-hour workday)
        } else if trimmed.contains("h") {
            return value * 3600 // hours
        } else if trimmed.contains("m") {
            return value * 60 // minutes
        }

        return nil
    }
}
