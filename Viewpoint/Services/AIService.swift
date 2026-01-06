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

        // Build conversation context asynchronously then proceed with chat
        Task {
            let context = await buildContext()
            let systemPrompt = buildSystemPrompt(context: context)

            await sendMessageWithContext(
                client: client,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                conversationHistory: conversationHistory,
                onChunk: onChunk,
                onComplete: onComplete
            )
        }
    }

    /// Send message with action history for ReAct pattern continuation
    func sendMessageWithActionHistory(
        userGoal: String,
        actionHistory: [(action: AIAction, result: ToolResult)],
        conversationHistory: [Message],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) {
        guard let client = client else {
            onComplete(.failure(VertexAIError.missingCredentials))
            return
        }

        // Build conversation context with action history
        Task {
            let context = await buildContext(actionHistory: actionHistory, userGoal: userGoal)
            let systemPrompt = buildSystemPrompt(context: context)

            // Continuation message asks AI to analyze results and decide next steps
            let continuationMessage = "Based on the action results above, what should I do next to complete the goal?"

            await sendMessageWithContext(
                client: client,
                systemPrompt: systemPrompt,
                userMessage: continuationMessage,
                conversationHistory: conversationHistory,
                onChunk: onChunk,
                onComplete: onComplete
            )
        }
    }

    private func sendMessageWithContext(
        client: VertexAIClient,
        systemPrompt: String,
        userMessage: String,
        conversationHistory: [Message],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) async {

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
                    Logger.shared.info("AI full response: \(fullResponse)")

                    // Try new JSON-based actions first
                    let actions = self.parseActions(from: fullResponse)

                    // Fall back to legacy intents if no actions found
                    let intents = self.parseIntents(from: fullResponse)

                    // Detect if task is complete (ReAct pattern)
                    let taskComplete = self.detectTaskComplete(from: fullResponse)

                    Logger.shared.info("Parsed \(actions.count) actions and \(intents.count) legacy intents from response (taskComplete: \(taskComplete))")

                    // Clean the response text (remove action/command lines)
                    let cleanedText = self.cleanResponseText(fullResponse)

                    // Create response - prefer actions if available
                    let response: AIResponse
                    if !actions.isEmpty {
                        response = AIResponse(
                            text: cleanedText,
                            actions: actions,
                            taskComplete: taskComplete,
                            inputTokens: usage.inputTokens,
                            outputTokens: usage.outputTokens
                        )
                    } else {
                        response = AIResponse(
                            text: cleanedText,
                            intents: intents,
                            inputTokens: usage.inputTokens,
                            outputTokens: usage.outputTokens
                        )
                    }
                    onComplete(.success(response))

                case .failure(let error):
                    onComplete(.failure(error))
                }
            }
        )
    }

    // MARK: - Context Building

    private func buildContext(
        actionHistory: [(action: AIAction, result: ToolResult)]? = nil,
        userGoal: String? = nil
    ) async -> AIContext {
        let currentUser = UserDefaults.standard.string(forKey: "jiraEmail") ?? "unknown"

        // Get selected issues by mapping IDs to actual issues
        let selectedIssues = await MainActor.run {
            jiraService.selectedIssues.compactMap { selectedID in
                jiraService.issues.first { $0.id == selectedID }
            }
        }

        // Fetch full details for selected issues (description, comments, changelog)
        // Limit to first 3 to avoid too much context
        var issueDetails: [IssueDetails] = []
        for issue in selectedIssues.prefix(3) {
            let result = await jiraService.fetchIssueDetails(issueKey: issue.key)
            if let details = result.details {
                issueDetails.append(details)
            }
        }

        let filters = await MainActor.run { jiraService.filters }
        let issues = await MainActor.run { jiraService.issues }
        let projects = await MainActor.run { Array(jiraService.availableProjects) }
        let sprints = await MainActor.run { jiraService.availableSprints }
        let epics = await MainActor.run { Array(jiraService.availableEpics) }
        let statuses = await MainActor.run { Array(jiraService.availableStatuses) }
        let resolutions = await MainActor.run { Array(jiraService.availableResolutions) }

        return AIContext(
            currentUser: currentUser,
            selectedIssues: selectedIssues,
            selectedIssueDetails: issueDetails,
            currentFilters: filters,
            visibleIssues: Array(issues.prefix(20)), // Top 20 for context
            availableProjects: projects,
            availableSprints: sprints,
            availableEpics: epics,
            availableStatuses: statuses,
            availableResolutions: resolutions,
            lastSearchResults: nil,
            lastCreatedIssue: nil,
            actionHistory: actionHistory,
            userGoal: userGoal
        )
    }

    private func buildSystemPrompt(context: AIContext) -> String {
        // Build the selected issues section with strong emphasis
        let selectedIssuesSection: String
        if !context.selectedIssues.isEmpty {
            let issueKeys = context.selectedIssues.map { $0.key }.joined(separator: ", ")
            selectedIssuesSection = """

        ⚠️ CURRENTLY SELECTED ISSUES (CRITICAL - USE THESE FOR OPERATIONS):
        The user has \(context.selectedIssues.count) issue(s) currently selected: \(issueKeys)

        IMPORTANT RULES FOR SELECTED ISSUES:
        1. When the user says "this", "it", "the issue", "these", "them", "try again", "retry", or asks to perform any action without explicitly specifying an issue key, ALWAYS use: \(issueKeys)
        2. IGNORE any issue keys mentioned in the conversation history above - the user may have changed their selection
        3. The selected issues shown here are the CURRENT selection and take priority over everything else
        4. If the user previously worked on a different issue (e.g., SETI-1063) but now has \(issueKeys) selected, use \(issueKeys)

        Selected Issue Details:
        \(describeSelectedIssues(context.selectedIssues))
        \(describeSelectedIssueDetails(context.selectedIssueDetails))
        """
        } else {
            selectedIssuesSection = ""
        }

        // Build action history feedback section (for ReAct pattern)
        let actionHistorySection: String
        if let history = context.actionHistory, !history.isEmpty, let goal = context.userGoal {
            var historyText = """

            ⚡ PREVIOUS ACTIONS TAKEN (ReAct Loop):
            User's Goal: "\(goal)"

            You have already taken these actions toward the goal:

            """

            for (index, (action, result)) in history.enumerated() {
                let statusIcon = result.success ? "✓" : "✗"
                let status = result.success ? "Success" : "Failed"
                historyText += """
                \(index + 1). \(action.tool) \(statusIcon) \(status)
                   Args: \(action.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
                   Result: \(result.message ?? "No message")

                """

                // Include data if it provides useful information
                if let data = result.data {
                    // Handle array of issue keys (from search_issues)
                    if let issueKeys = data as? [String], !issueKeys.isEmpty {
                        historyText += "   Found Issues: \(issueKeys.joined(separator: ", "))\n"
                    }
                    // Handle dictionary with issues array
                    else if let issuesData = data as? [String: Any],
                       let issues = issuesData["issues"] as? [[String: Any]],
                       !issues.isEmpty {
                        historyText += "   Found Issues: \(issues.compactMap { $0["key"] as? String }.joined(separator: ", "))\n"
                    }
                    // Handle single issue key string
                    else if let issueKey = data as? String {
                        historyText += "   Issue Key: \(issueKey)\n"
                    }
                }
            }

            historyText += """

            IMPORTANT: Based on these results, determine if you need to take additional actions to FULLY complete the user's goal.
            - If you found issue keys above, USE THEM in your next actions (e.g., assign_issue, update_issue)
            - DO NOT search again for issues you've already found - use the keys from the results above
            - When assigning to "me" or "the current user", use the email: \(context.currentUser)
            - If multiple issues need the same operation, generate multiple actions (one per issue)
            - If more work is needed, generate the next action(s) using the issue keys and data from above
            - If the goal is FULLY achieved, respond with your summary and end with: TASK_COMPLETE

            """

            actionHistorySection = historyText
        } else {
            actionHistorySection = ""
        }

        // Get tools from CapabilityRegistry
        let toolsPrompt = CapabilityRegistry.shared.generateToolsPrompt()
        let actionFormat = CapabilityRegistry.shared.generateActionFormatPrompt()

        return """
        You are Indigo, an AI assistant for Jira integrated into Viewpoint, a macOS Jira client.

        Your role is to help users manage their Jira issues using natural language. You can search for issues, update fields, create new issues, log work, and more.
        \(selectedIssuesSection)\(actionHistorySection)

        ## Current Context
        - Current user: \(context.currentUser)
        - Available projects: \(context.availableProjects.prefix(20).joined(separator: ", "))\(context.availableProjects.count > 20 ? " (and \(context.availableProjects.count - 20) more)" : "")
        - Available statuses: \(context.availableStatuses.joined(separator: ", "))
        - Available resolutions: \(context.availableResolutions.joined(separator: ", "))
        - Active filters: \(describeFilters(context.currentFilters))
        - Visible issues: \(context.visibleIssues.count) issues currently loaded
        - Available sprints (active/future only):
          \(context.availableSprints.filter { $0.state.lowercased() != "closed" }.prefix(10).map { "\($0.name) (ID: \($0.id), state: \($0.state))" }.joined(separator: "\n          "))

        ## Answering Questions
        When the user asks questions about selected issues (e.g., "what is this about?", "summarize this"), use the SELECTED ISSUE DETAILS above to answer directly. Be conversational and helpful.

        \(actionFormat)

        \(toolsPrompt)

        ## Important Guidelines
        - Always explain what you're doing in plain language alongside the action
        - When closing/resolving issues, include both status and resolution fields
        - For time logging, convert durations to seconds (1h = 3600, 2h = 7200, etc.)
        - For estimates, pass time strings like "2h" or "30m" directly
        - Use "currentUser()" in JQL for the current user's issues
        - Be concise and helpful

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
            let reporter = issue.reporter ?? "Unknown"
            return "\(issue.key) [\(issue.status), Assignee: \(assignee), Reporter: \(reporter)]: \(issue.summary)"
        }.joined(separator: "\n  ")
    }

    private func describeSelectedIssueDetails(_ details: [IssueDetails]) -> String {
        guard !details.isEmpty else { return "" }

        var result = "\n- SELECTED ISSUE DETAILS:\n"

        for detail in details {
            let pcmMasterValue = detail.issue.pcmMaster?.label ?? detail.issue.pcmMaster?.objectKey ?? "None"
            result += """

              \(detail.issue.key): \(detail.issue.summary)
              Type: \(detail.issue.issueType) | Status: \(detail.issue.status) | Priority: \(detail.issue.priority ?? "None")
              Assignee: \(detail.issue.assignee ?? "Unassigned") | Reporter: \(detail.issue.reporter ?? "Unknown") | PCM Master: \(pcmMasterValue)
            """

            if let description = detail.description, !description.isEmpty {
                // Truncate very long descriptions
                let truncated = description.count > 500 ? String(description.prefix(500)) + "..." : description
                result += "\n  Description: \(truncated)"
            }

            if !detail.comments.isEmpty {
                result += "\n  Recent Comments (\(detail.comments.count) total):"
                // Show last 3 comments
                for comment in detail.comments.suffix(3) {
                    let truncatedBody = comment.body.count > 200 ? String(comment.body.prefix(200)) + "..." : comment.body
                    result += "\n    - \(comment.author): \(truncatedBody)"
                }
            }

            result += "\n"
        }

        return result
    }

    // MARK: - Shared Field Validation

    /// Core LLM-based field matching - shared between CREATE and UPDATE operations
    private func matchFieldsWithLLM(
        userFields: [String: Any],
        fieldDescriptions: [[String: Any]],
        context: String
    ) async -> (mappedFields: [String: Any]?, clarificationNeeded: String?) {

        guard let fieldDescriptionsData = try? JSONSerialization.data(withJSONObject: fieldDescriptions, options: [.prettyPrinted]),
              let fieldDescriptionsJSON = String(data: fieldDescriptionsData, encoding: .utf8) else {
            Logger.shared.error("Failed to serialize field descriptions")
            return (nil, nil)
        }

        let prompt = """
        You are a field mapping expert for Jira. Match user-provided values to Jira's allowed values.

        USER PROVIDED VALUES:
        \(userFields.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))

        AVAILABLE FIELDS AND ALLOWED VALUES:
        \(fieldDescriptionsJSON)

        CONTEXT: \(context)

        YOUR TASK:
        1. Map each user value to the correct allowed value from the list
        2. Handle spelling variations (e.g., "Cancelled" → "Canceled")
        3. Handle synonyms (e.g., "wont do" → "Won't Do", "done" → "Done")
        4. If a value cannot be matched, use the closest semantic match
        5. If critical information is missing or ambiguous, respond with "CLARIFICATION_NEEDED: <your question>"

        Respond with valid JSON mapping field keys to matched values:
        ```json
        {
          "fieldKey": "matched_value"
        }
        ```
        """

        guard let client = client else {
            Logger.shared.error("AI client not configured for field validation")
            return (nil, nil)
        }

        do {
            let result = try await client.generateContent(prompt: prompt)
            Logger.shared.info("Field matching LLM response: \(result)")

            // Check if clarification is needed
            if result.contains("CLARIFICATION_NEEDED:") {
                let clarification = result.replacingOccurrences(of: "CLARIFICATION_NEEDED:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return (nil, clarification)
            }

            // Parse JSON response
            if let jsonStart = result.range(of: "```json"),
               let jsonEnd = result.range(of: "```", range: jsonStart.upperBound..<result.endIndex) {
                let jsonString = String(result[jsonStart.upperBound..<jsonEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

                if let jsonData = jsonString.data(using: .utf8),
                   let mappedFields = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    Logger.shared.info("Successfully matched fields: \(mappedFields)")
                    return (mappedFields, nil)
                }
            }

            Logger.shared.warning("Could not parse LLM response")
            return (nil, nil)

        } catch {
            Logger.shared.error("LLM field matching failed: \(error)")
            return (nil, nil)
        }
    }

    /// Extract field descriptions from Jira metadata
    private func extractFieldDescriptions(from metadata: [String: Any]) -> [[String: Any]] {
        var fieldDescriptions: [[String: Any]] = []

        for (fieldKey, fieldData) in metadata {
            guard let fieldDict = fieldData as? [String: Any] else { continue }

            var description: [String: Any] = [
                "key": fieldKey,
                "name": fieldDict["name"] as? String ?? fieldKey,
                "required": fieldDict["required"] as? Bool ?? false
            ]

            if let allowedValues = fieldDict["allowedValues"] as? [[String: Any]] {
                let values = allowedValues.compactMap { $0["name"] as? String ?? $0["value"] as? String }
                if !values.isEmpty {
                    description["allowedValues"] = values
                }
            }

            fieldDescriptions.append(description)
        }

        return fieldDescriptions
    }

    // MARK: - CREATE Field Validation

    func validateAndMapFields(userFields: [String: Any], projectKey: String, issueType: String = "Story") async -> (mappedFields: [String: Any]?, clarificationNeeded: String?) {
        // Fetch metadata for this project/issue type
        guard let metadata = await jiraService.fetchCreateMetadata(projectKey: projectKey, issueType: issueType) else {
            Logger.shared.error("Failed to fetch field metadata for \(projectKey)/\(issueType)")
            return (userFields, nil)
        }

        let fieldDescriptions = extractFieldDescriptions(from: metadata)

        if fieldDescriptions.isEmpty {
            return (userFields, nil)
        }

        let context = "Creating a \(issueType) in project \(projectKey). Current user: \(jiraService.config.jiraEmail)"

        let (mappedFields, clarification) = await matchFieldsWithLLM(
            userFields: userFields,
            fieldDescriptions: fieldDescriptions,
            context: context
        )

        if let clarification = clarification {
            return (nil, clarification)
        }

        // Merge mapped fields with original (mapped takes precedence)
        if let mapped = mappedFields {
            var result = userFields
            for (key, value) in mapped {
                result[key] = value
            }
            return (result, nil)
        }

        return (userFields, nil)
    }

    // MARK: - UPDATE Field Validation

    func validateUpdateFields(issueKey: String, userFields: [String: Any]) async -> (mappedFields: [String: Any]?, clarificationNeeded: String?) {
        // Check if this involves a status change with additional fields
        guard userFields["status"] != nil else {
            // No status change - return fields as-is
            return (userFields, nil)
        }

        // Only validate if there are fields besides status
        let fieldsToValidate = userFields.filter { $0.key != "status" }
        if fieldsToValidate.isEmpty {
            return (userFields, nil)
        }

        // Fetch available transitions with field definitions
        let transitionsURL = "\(jiraService.config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/transitions?expand=transitions.fields"
        guard let url = URL(string: transitionsURL) else {
            Logger.shared.error("Invalid URL for fetching transitions")
            return (userFields, nil)
        }

        let request = jiraService.createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let transitions = json["transitions"] as? [[String: Any]] else {
                Logger.shared.error("Failed to parse transitions response")
                return (userFields, nil)
            }

            // Find matching transition and extract field metadata
            let targetStatus = (userFields["status"] as? String)?.lowercased() ?? ""
            var transitionFields: [String: Any]?

            for trans in transitions {
                if let transName = trans["name"] as? String,
                   let to = trans["to"] as? [String: Any],
                   let toStatus = to["name"] as? String {
                    if transName.lowercased().contains(targetStatus) ||
                       toStatus.lowercased().contains(targetStatus) ||
                       targetStatus.contains(transName.lowercased()) ||
                       targetStatus.contains(toStatus.lowercased()) {
                        transitionFields = trans["fields"] as? [String: Any]
                        break
                    }
                }
            }

            guard let fields = transitionFields else {
                Logger.shared.warning("No matching transition found or no fields to validate")
                return (userFields, nil)
            }

            let fieldDescriptions = extractFieldDescriptions(from: fields)

            if fieldDescriptions.isEmpty {
                return (userFields, nil)
            }

            let context = "Transitioning issue \(issueKey) to status '\(userFields["status"] ?? "unknown")'"

            let (mappedFields, clarification) = await matchFieldsWithLLM(
                userFields: fieldsToValidate,
                fieldDescriptions: fieldDescriptions,
                context: context
            )

            if let clarification = clarification {
                return (nil, clarification)
            }

            // Merge mapped fields back with original (including status)
            if let mapped = mappedFields {
                var result = userFields
                for (key, value) in mapped {
                    result[key] = value
                }
                return (result, nil)
            }

            return (userFields, nil)

        } catch {
            Logger.shared.error("Failed to validate update fields: \(error)")
            return (userFields, nil)
        }
    }

    // MARK: - Intent Parsing

    private func parseIntents(from response: String) -> [AIResponse.Intent] {
        // Look for special format markers in the response
        let lines = response.components(separatedBy: "\n")
        var intents: [AIResponse.Intent] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // JQL Search (handle both "JQL:" and "SEARCH:" prefixes)
            if trimmed.hasPrefix("JQL:") || trimmed.hasPrefix("SEARCH:") {
                var jql = trimmed
                if jql.hasPrefix("JQL:") {
                    jql = jql.replacingOccurrences(of: "JQL:", with: "")
                } else {
                    jql = jql.replacingOccurrences(of: "SEARCH:", with: "")
                }
                jql = jql.trimmingCharacters(in: .whitespaces)
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

            // Get available transitions
            if trimmed.hasPrefix("GET_TRANSITIONS:") {
                let issueKey = trimmed.replacingOccurrences(of: "GET_TRANSITIONS:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.getTransitions(issueKey: issueKey))
                continue
            }

            // Sprint lookup
            if trimmed.hasPrefix("SPRINT:") {
                let query = trimmed.replacingOccurrences(of: "SPRINT:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.sprintLookup(query: query, projectKey: nil))
                continue
            }

            // Component lookup
            if trimmed.hasPrefix("COMPONENTS:") {
                let projectKey = trimmed.replacingOccurrences(of: "COMPONENTS:", with: "").trimmingCharacters(in: .whitespaces)
                intents.append(.componentLookup(projectKey: projectKey))
                continue
            }

            // Classification lookup: CLASSIFY: ISSUE-123 | query
            if trimmed.hasPrefix("CLASSIFY:") {
                let content = trimmed.replacingOccurrences(of: "CLASSIFY:", with: "").trimmingCharacters(in: .whitespaces)
                let parts = content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    let issueKey = parts[0]
                    let query = parts[1]
                    intents.append(.classificationLookup(issueKey: issueKey, query: query))
                }
                continue
            }

            // Classification select: SELECT_CLASSIFICATION: ISSUE-123 | 1
            if trimmed.hasPrefix("SELECT_CLASSIFICATION:") {
                let content = trimmed.replacingOccurrences(of: "SELECT_CLASSIFICATION:", with: "").trimmingCharacters(in: .whitespaces)
                let parts = content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2, let index = Int(parts[1]) {
                    let issueKey = parts[0]
                    intents.append(.classificationSelect(issueKey: issueKey, optionIndex: index))
                }
                continue
            }

            // PCM lookup: PCM: ISSUE-123 | query
            if trimmed.hasPrefix("PCM:") {
                let content = trimmed.replacingOccurrences(of: "PCM:", with: "").trimmingCharacters(in: .whitespaces)
                let parts = content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    let issueKey = parts[0]
                    let query = parts[1]
                    intents.append(.pcmLookup(issueKey: issueKey, query: query))
                }
                continue
            }

            // PCM select: SELECT_PCM: ISSUE-123 | 1
            if trimmed.hasPrefix("SELECT_PCM:") {
                let content = trimmed.replacingOccurrences(of: "SELECT_PCM:", with: "").trimmingCharacters(in: .whitespaces)
                let parts = content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2, let index = Int(parts[1]) {
                    let issueKey = parts[0]
                    intents.append(.pcmSelect(issueKey: issueKey, optionIndex: index))
                }
                continue
            }
        }

        return intents
    }

    // MARK: - Action Parsing (New JSON-based system)

    private func parseActions(from response: String) -> [AIAction] {
        // Look for ACTION: lines with JSON payload
        let lines = response.components(separatedBy: "\n")
        var actions: [AIAction] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse ACTION: {"tool": "...", "args": {...}}
            if trimmed.hasPrefix("ACTION:") {
                let jsonPart = trimmed.replacingOccurrences(of: "ACTION:", with: "").trimmingCharacters(in: .whitespaces)

                // Try to parse as JSON
                guard let jsonData = jsonPart.data(using: .utf8) else {
                    Logger.shared.warning("Failed to convert ACTION to data: \(jsonPart)")
                    continue
                }

                do {
                    let action = try JSONDecoder().decode(AIAction.self, from: jsonData)
                    actions.append(action)
                    Logger.shared.debug("Parsed action: \(action.tool) with args: \(action.arguments)")
                } catch {
                    Logger.shared.warning("Failed to parse ACTION JSON: \(error.localizedDescription) - \(jsonPart)")
                }
            }
        }

        return actions
    }

    /// Detect if AI has indicated the task is complete (ReAct pattern)
    private func detectTaskComplete(from response: String) -> Bool {
        let uppercased = response.uppercased()
        return uppercased.contains("TASK_COMPLETE") ||
               uppercased.contains("TASK COMPLETE") ||
               uppercased.contains("GOAL COMPLETE") ||
               uppercased.contains("GOAL ACHIEVED")
    }

    /// Clean the AI response text by removing ACTION: lines
    private func cleanResponseText(_ response: String) -> String {
        let lines = response.components(separatedBy: "\n")
        let cleanedLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Remove action lines and legacy command lines
            return !trimmed.hasPrefix("ACTION:") &&
                   !trimmed.hasPrefix("JQL:") &&
                   !trimmed.hasPrefix("SEARCH:") &&
                   !trimmed.hasPrefix("UPDATE:") &&
                   !trimmed.hasPrefix("CREATE:") &&
                   !trimmed.hasPrefix("LOG:") &&
                   !trimmed.hasPrefix("COMMENT:") &&
                   !trimmed.hasPrefix("DELETE:") &&
                   !trimmed.hasPrefix("ASSIGN:") &&
                   !trimmed.hasPrefix("WATCH:") &&
                   !trimmed.hasPrefix("LINK:") &&
                   !trimmed.hasPrefix("CHANGELOG:") &&
                   !trimmed.hasPrefix("DETAIL:") &&
                   !trimmed.hasPrefix("GET_TRANSITIONS:") &&
                   !trimmed.hasPrefix("SPRINT:") &&
                   !trimmed.hasPrefix("COMPONENTS:") &&
                   !trimmed.hasPrefix("CLASSIFY:") &&
                   !trimmed.hasPrefix("SELECT_CLASSIFICATION:") &&
                   !trimmed.hasPrefix("PCM:") &&
                   !trimmed.hasPrefix("SELECT_PCM:")
        }
        return cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
