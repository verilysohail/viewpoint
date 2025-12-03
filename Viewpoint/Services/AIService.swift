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
                        intents: self.parseIntents(from: fullResponse),
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

        // Get selected issues by mapping IDs to actual issues
        let selectedIssues = jiraService.selectedIssues.compactMap { selectedID in
            jiraService.issues.first { $0.id == selectedID }
        }

        return AIContext(
            currentUser: currentUser,
            selectedIssues: selectedIssues,
            currentFilters: jiraService.filters,
            visibleIssues: Array(jiraService.issues.prefix(20)), // Top 20 for context
            availableProjects: Array(jiraService.availableProjects),
            availableSprints: jiraService.availableSprints,
            availableEpics: Array(jiraService.availableEpics),
            availableStatuses: Array(jiraService.availableStatuses),
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
        - Available statuses: \(context.availableStatuses.joined(separator: ", "))
        - Active filters: \(describeFilters(context.currentFilters))
        - Visible issues: \(context.visibleIssues.count) issues currently loaded
        - Available sprints: \(context.availableSprints.map { $0.name }.joined(separator: ", "))
        \(context.selectedIssues.isEmpty ? "" : "- SELECTED ISSUES (\(context.selectedIssues.count)): \(describeSelectedIssues(context.selectedIssues))")

        IMPORTANT INSTRUCTIONS:
        You can perform these Jira operations by including special format markers in your response:

        1. SEARCH: Generate JQL queries
           Format: `JQL: <query>`
           Example: JQL: assignee = currentUser() AND sprint in openSprints()

        2. CREATE: Create new issues
           Format: `CREATE: project=X | summary=Y | type=Z | ...`
           Available fields:
           - project: Project key (required)
           - summary: Issue summary (required)
           - type: Issue type (Bug, Story, Task, etc.)
           - assignee: User email (use \(context.currentUser) for yourself)
           - estimate: Time estimate (e.g., "30m", "2h", "1d")
           - sprint: Sprint name or "current" for active sprint
           - epic: Epic name or key
           - components: Component names (comma-separated)
           - priority: Priority level
           - labels: Labels (comma-separated)
           Example: CREATE: project=SETI | summary=Fix bug | type=Bug | assignee=\(context.currentUser) | estimate=2h | sprint=current | components=Management Tasks

        3. UPDATE: Update issue fields (summary, description, assignee, priority, labels, components, estimates, sprint, epic, status)
           Format: `UPDATE: <key> | field=value | field2=value2`
           Example: UPDATE: SETI-123 | summary=New title | priority=High | labels=urgent,bug
           Status updates: You can use natural language like "done", "closed", "complete", "in progress", "cancel", etc.
           The system will intelligently match these to the correct Jira transition. The "Available statuses" list
           shows statuses from currently loaded issues, but other statuses may be available for specific issues.

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

        10. CHANGELOG: Fetch change history for issue
           Format: `CHANGELOG: <key>`
           Example: CHANGELOG: SETI-123

        11. DETAIL: Open detailed view of issue with comments, history, and all data
           Format: `DETAIL: <key>`
           Example: DETAIL: SETI-123
           Use this when user asks for "details", "full information", "comments", or "show me" an issue

        IMPORTANT:
        - Always explain what you're doing in plain language alongside the operation
        - You can update multiple fields in one UPDATE command
        - For sprint, use "sprint=current" to assign to the active sprint for that project
        - When creating issues, the sprint will be automatically scoped to the project's board
        - For estimates, use format like "30m", "2h", "1d" (minutes, hours, days)
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

    private func describeSelectedIssues(_ issues: [JiraIssue]) -> String {
        return issues.map { issue in
            let assignee = issue.assignee ?? "Unassigned"
            return "\(issue.key) [\(issue.status), \(assignee)]: \(issue.summary)"
        }.joined(separator: "\n  ")
    }

    // MARK: - Field Validation and Mapping

    func validateAndMapFields(userFields: [String: Any], projectKey: String, issueType: String = "Story") async -> (mappedFields: [String: Any]?, clarificationNeeded: String?) {
        // Fetch metadata for this project/issue type
        guard let metadata = await jiraService.fetchCreateMetadata(projectKey: projectKey, issueType: issueType) else {
            Logger.shared.error("Failed to fetch field metadata for \(projectKey)/\(issueType)")
            return (userFields, nil) // Fallback to original fields
        }

        // Build a summary of available fields for the LLM
        var fieldDescriptions: [[String: Any]] = []
        for (fieldKey, fieldData) in metadata {
            guard let fieldDict = fieldData as? [String: Any] else { continue }

            var description: [String: Any] = [
                "key": fieldKey,
                "name": fieldDict["name"] as? String ?? fieldKey,
                "required": fieldDict["required"] as? Bool ?? false,
                "schema": fieldDict["schema"] as Any
            ]

            // Add allowed values if present
            if let allowedValues = fieldDict["allowedValues"] as? [[String: Any]] {
                let values = allowedValues.compactMap { $0["name"] as? String ?? $0["value"] as? String }
                description["allowedValues"] = values
            }

            fieldDescriptions.append(description)
        }

        // Convert to JSON for the LLM
        guard let fieldDescriptionsData = try? JSONSerialization.data(withJSONObject: fieldDescriptions, options: [.prettyPrinted]),
              let fieldDescriptionsJSON = String(data: fieldDescriptionsData, encoding: .utf8) else {
            Logger.shared.error("Failed to serialize field descriptions")
            return (userFields, nil)
        }

        // Use LLM to map user fields to Jira fields
        let prompt = """
        You are a field mapping expert for Jira. Given user-provided fields and the available Jira field schema, map the user's intent to the correct Jira field format.

        USER PROVIDED FIELDS:
        \(userFields.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))

        AVAILABLE JIRA FIELDS FOR \(projectKey)/\(issueType):
        \(fieldDescriptionsJSON)

        ADDITIONAL CONTEXT:
        - Current user email: \(jiraService.config.jiraEmail)
        - If user wants "current sprint", you need to return: sprint=current (this will be resolved server-side)
        - Time estimates should be in Jira format: "30m", "2h", "1d"
        - For assignee, use the email address provided

        YOUR TASK:
        1. Map each user field to the correct Jira field key
        2. Validate that values are acceptable
        3. Check if any required fields are missing
        4. If anything is ambiguous or missing, respond with "CLARIFICATION_NEEDED: <your question>"
        5. Otherwise, respond with valid JSON mapping in this format:

        ```json
        {
          "fieldKey1": "value1",
          "fieldKey2": "value2"
        }
        ```

        For example:
        - User's "estimate" or "originalEstimate" maps to "timetracking" field with format {"originalEstimate": "value"}
        - User's "assignee" maps to "assignee" field
        - User's "sprint" maps to "customfield_10020" (sprint field)
        - User's "epic" maps to "customfield_10014" (epic field)
        - User's "components" may need to be formatted as array of objects

        RESPOND NOW:
        """

        // Make synchronous LLM call for field mapping
        guard let client = client else {
            Logger.shared.error("AI client not configured for field validation")
            return (userFields, nil)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var mappingResult: String?
        var mappingError: Error?

        // Use the same client to make a mapping call
        Task {
            do {
                let response = try await client.generateContent(prompt: prompt)
                mappingResult = response
                semaphore.signal()
            } catch {
                mappingError = error
                semaphore.signal()
            }
        }

        semaphore.wait()

        if let error = mappingError {
            Logger.shared.error("Field mapping LLM call failed: \(error)")
            return (userFields, nil)
        }

        guard let result = mappingResult else {
            Logger.shared.error("No result from field mapping LLM")
            return (userFields, nil)
        }

        Logger.shared.info("Field mapping LLM response: \(result)")

        // Check if clarification is needed
        if result.contains("CLARIFICATION_NEEDED:") {
            let clarification = result.replacingOccurrences(of: "CLARIFICATION_NEEDED:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, clarification)
        }

        // Parse the JSON response
        if let jsonStart = result.range(of: "```json"),
           let jsonEnd = result.range(of: "```", range: jsonStart.upperBound..<result.endIndex) {
            let jsonString = String(result[jsonStart.upperBound..<jsonEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = jsonString.data(using: .utf8),
               let mappedFields = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                Logger.shared.info("Successfully mapped fields: \(mappedFields)")
                return (mappedFields, nil)
            }
        }

        // Fallback: use original fields
        Logger.shared.warning("Could not parse LLM mapping response, using original fields")
        return (userFields, nil)
    }

    // MARK: - Intent Parsing

    private func parseIntents(from response: String) -> [AIResponse.Intent] {
        // Look for special format markers in the response
        let lines = response.components(separatedBy: "\n")
        var intents: [AIResponse.Intent] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // JQL Search
            if trimmed.hasPrefix("JQL:") {
                let jql = trimmed.replacingOccurrences(of: "JQL:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.search(jql: jql))
                continue
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

                intents.append(.update(issueKey: issueKey, fields: fields))
                continue
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

                intents.append(.create(fields: fields))
                continue
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
                        intents.append(.logWork(issueKey: issueKey, timeSeconds: seconds))
                    }
                }
                continue
            }

            // Add comment
            if trimmed.hasPrefix("COMMENT:") {
                let parts = trimmed.replacingOccurrences(of: "COMMENT:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                let comment = parts[1]
                intents.append(.addComment(issueKey: issueKey, comment: comment))
                continue
            }

            // Delete issue
            if trimmed.hasPrefix("DELETE:") {
                let issueKey = trimmed.replacingOccurrences(of: "DELETE:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.deleteIssue(issueKey: issueKey))
                continue
            }

            // Assign issue
            if trimmed.hasPrefix("ASSIGN:") {
                let parts = trimmed.replacingOccurrences(of: "ASSIGN:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                let assignee = parts[1]
                intents.append(.assignIssue(issueKey: issueKey, assignee: assignee))
                continue
            }

            // Add watcher
            if trimmed.hasPrefix("WATCH:") {
                let parts = trimmed.replacingOccurrences(of: "WATCH:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                guard parts.count >= 2 else { continue }
                let issueKey = parts[0]
                let watcher = parts[1]
                intents.append(.addWatcher(issueKey: issueKey, watcher: watcher))
                continue
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
                intents.append(.linkIssues(issueKey: issueKey, linkedIssue: linkedIssue, linkType: linkType))
                continue
            }

            // Fetch changelog
            if trimmed.hasPrefix("CHANGELOG:") {
                let issueKey = trimmed.replacingOccurrences(of: "CHANGELOG:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.fetchChangelog(issueKey: issueKey))
                continue
            }

            // Show issue detail
            if trimmed.hasPrefix("DETAIL:") {
                let issueKey = trimmed.replacingOccurrences(of: "DETAIL:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.showIssueDetail(issueKey: issueKey))
                continue
            }
        }

        return intents
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
