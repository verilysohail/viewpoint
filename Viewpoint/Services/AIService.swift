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
                    let intents = self.parseIntents(from: fullResponse)
                    Logger.shared.info("Parsed \(intents.count) intents from response")
                    let response = AIResponse(
                        text: fullResponse,
                        intents: intents,
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

    private func buildContext() async -> AIContext {
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
            lastCreatedIssue: nil
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

        return """
        You are Indigo, an AI assistant for Jira integrated into Viewpoint, a macOS Jira client.

        Your role is to help users manage their Jira issues using natural language. You can:
        1. Search for issues using JQL (Jira Query Language)
        2. Update issue fields (status, assignee, estimates, etc.)
        3. Create new issues
        4. Log work on issues
        5. Provide summaries and insights
        \(selectedIssuesSection)

        CURRENT CONTEXT:
        - Current user: \(context.currentUser)
        - Available projects: \(context.availableProjects.joined(separator: ", "))
        - Available statuses: \(context.availableStatuses.joined(separator: ", "))
        - Available resolutions: \(context.availableResolutions.joined(separator: ", "))
        - Active filters: \(describeFilters(context.currentFilters))
        - Visible issues: \(context.visibleIssues.count) issues currently loaded
        - Available sprints (with dates):
          \(context.availableSprints.map { "\($0.name) (ID: \($0.id), \($0.startDate ?? "no start") - \($0.endDate ?? "no end"), state: \($0.state))" }.joined(separator: "\n          "))

        ANSWERING QUESTIONS:
        When the user asks questions about selected issues (e.g., "what is this about?", "summarize this", "who worked on this?", "what are the comments?"), you should:
        1. Use the SELECTED ISSUE DETAILS above to answer directly in natural language
        2. Do NOT use DETAIL: command for simple questions - you already have the information
        3. Only use DETAIL: if you need more information than what's provided above
        4. Be conversational and helpful when answering questions

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

        3. UPDATE: Update issue fields (summary, description, assignee, priority, labels, components, estimates, sprint, epic, status, resolution, pcmmaster)
           Format: `UPDATE: <key> | field=value | field2=value2`
           Example: UPDATE: SETI-123 | summary=New title | priority=High | labels=urgent,bug

           PCM MASTER FIELD:
           - pcmmaster: Set the PCM Master CMDB field (e.g., pcmmaster=Loom, pcmmaster=Slack)
           - Use "none" to clear the field: pcmmaster=none
           - The system will search for matching PCM Master entries by name

           STATUS UPDATES WITH RESOLUTION:
           When closing/cancelling an issue, ALWAYS use both status and resolution:
           - For status field: Use natural language like "close", "closed", "done" - the system will match to correct transition
           - For resolution field: Match to available resolutions from CURRENT CONTEXT (Done, Won't Do, Cancelled, etc.)

           Examples:
           - User says "cancel this" → UPDATE: SETI-123 | status=close | resolution=Cancelled
           - User says "close as won't do" → UPDATE: SETI-123 | status=close | resolution=Won't Do
           - User says "mark as done" → UPDATE: SETI-123 | status=close | resolution=Done
           - User says "complete this" → UPDATE: SETI-123 | status=close | resolution=Done

           For other status changes (not closing):
           - "start this" → UPDATE: SETI-123 | status=in progress
           - "put on hold" → UPDATE: SETI-123 | status=on hold

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

        12. GET_TRANSITIONS: Query available transitions and resolutions for an issue
           Format: `GET_TRANSITIONS: <key>`
           Example: GET_TRANSITIONS: SETI-123
           Returns available status transitions and their required fields (like resolution values)
           IMPORTANT: Use this BEFORE updating status when user mentions closing/cancelling with specific resolutions
           This tells you exactly which transitions are available and what resolution values you can use

        13. SPRINT: Look up sprint information (NOT via JQL - sprints are not issues!)
           Format: `SPRINT: <query>`
           Examples:
           - SPRINT: find sprint for first week of January
           - SPRINT: what sprints are active in SETI?
           - SPRINT: show me Sprint 42 details
           - SPRINT: what is the ID of the current sprint?
           The system will search available sprints and return matching sprint details inline.

        CRITICAL - SPRINTS ARE NOT ISSUES:
        - Sprints CANNOT be found using JQL search - JQL returns issues only
        - Viewpoint cannot display sprints in the issue list
        - When users ask about sprints (find a sprint, sprint ID, sprint dates), use the SPRINT: command above
        - You CAN still assign issues to sprints using UPDATE: issueKey | sprint=SprintName
        - The available sprints with their IDs and dates are listed above in CURRENT CONTEXT

        14. COMPONENTS: Look up available components for a project
           Format: `COMPONENTS: <projectKey>`
           Examples:
           - COMPONENTS: SETI
           - COMPONENTS: PROJ
           Returns all components configured for the project, including their descriptions and leads.
           Use this when users ask "what components are available for X?" or "show me components in X"

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

    private func describeSelectedIssueDetails(_ details: [IssueDetails]) -> String {
        guard !details.isEmpty else { return "" }

        var result = "\n- SELECTED ISSUE DETAILS:\n"

        for detail in details {
            let pcmMasterValue = detail.issue.pcmMaster?.label ?? detail.issue.pcmMaster?.objectKey ?? "None"
            result += """

              \(detail.issue.key): \(detail.issue.summary)
              Type: \(detail.issue.issueType) | Status: \(detail.issue.status) | Priority: \(detail.issue.priority ?? "None")
              Assignee: \(detail.issue.assignee ?? "Unassigned") | PCM Master: \(pcmMasterValue)
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
