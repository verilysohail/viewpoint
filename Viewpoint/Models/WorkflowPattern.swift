import Foundation

struct WorkflowPattern: Identifiable, Codable {
    let id: UUID
    var name: String
    var trigger: String
    var knowledge: String
    let createdAt: Date
    var lastModified: Date
    var isEnabled: Bool
    var isBuiltIn: Bool  // Default patterns shipped with the app

    init(id: UUID = UUID(), name: String, trigger: String, knowledge: String,
         createdAt: Date = Date(), lastModified: Date = Date(),
         isEnabled: Bool = true, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.knowledge = knowledge
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }
}

class WorkflowPatternsManager: ObservableObject {
    @Published var patterns: [WorkflowPattern] = []

    private let storageKey = "workflowPatterns"
    private let seedVersionKey = "workflowPatternsSeedVersion"
    private static let currentSeedVersion = 1

    init() {
        loadPatterns()
        seedDefaultPatternsIfNeeded()
    }

    func loadPatterns() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WorkflowPattern].self, from: data) {
            patterns = decoded
            Logger.shared.info("Loaded \(decoded.count) workflow patterns")
        }
    }

    func savePatterns() {
        if let encoded = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            Logger.shared.info("Saved \(patterns.count) workflow patterns")
        }
    }

    func addPattern(name: String, trigger: String, knowledge: String) {
        let pattern = WorkflowPattern(name: name, trigger: trigger, knowledge: knowledge)
        patterns.append(pattern)
        patterns.sort { $0.name.lowercased() < $1.name.lowercased() }
        savePatterns()
        Logger.shared.info("Added workflow pattern: \(name)")
    }

    func updatePattern(id: UUID, name: String, trigger: String, knowledge: String, isEnabled: Bool) {
        if let index = patterns.firstIndex(where: { $0.id == id }) {
            patterns[index].name = name
            patterns[index].trigger = trigger
            patterns[index].knowledge = knowledge
            patterns[index].isEnabled = isEnabled
            patterns[index].lastModified = Date()
            patterns.sort { $0.name.lowercased() < $1.name.lowercased() }
            savePatterns()
            Logger.shared.info("Updated workflow pattern: \(name)")
        }
    }

    func deletePattern(id: UUID) {
        // Don't allow deleting built-in patterns — disable them instead
        if let index = patterns.firstIndex(where: { $0.id == id }) {
            if patterns[index].isBuiltIn {
                patterns[index].isEnabled = false
                patterns[index].lastModified = Date()
            } else {
                patterns.remove(at: index)
            }
            savePatterns()
            Logger.shared.info("Deleted/disabled workflow pattern with ID: \(id)")
        }
    }

    func resetPattern(id: UUID) {
        // Reset a built-in pattern to its default content
        guard let index = patterns.firstIndex(where: { $0.id == id }),
              patterns[index].isBuiltIn else { return }

        if let defaultPattern = Self.defaultPatterns.first(where: { $0.name == patterns[index].name }) {
            patterns[index].trigger = defaultPattern.trigger
            patterns[index].knowledge = defaultPattern.knowledge
            patterns[index].isEnabled = true
            patterns[index].lastModified = Date()
            savePatterns()
            Logger.shared.info("Reset workflow pattern to default: \(patterns[index].name)")
        }
    }

    func togglePattern(id: UUID) {
        if let index = patterns.firstIndex(where: { $0.id == id }) {
            patterns[index].isEnabled.toggle()
            patterns[index].lastModified = Date()
            savePatterns()
            Logger.shared.info("Toggled workflow pattern: \(patterns[index].name) -> \(patterns[index].isEnabled)")
        }
    }

    var enabledPatterns: [WorkflowPattern] {
        patterns.filter { $0.isEnabled }
    }

    // MARK: - Default Pattern Seeding

    private func seedDefaultPatternsIfNeeded() {
        let lastSeedVersion = UserDefaults.standard.integer(forKey: seedVersionKey)
        if lastSeedVersion < Self.currentSeedVersion {
            seedDefaultPatterns()
            UserDefaults.standard.set(Self.currentSeedVersion, forKey: seedVersionKey)
        }
    }

    private func seedDefaultPatterns() {
        let existingNames = Set(patterns.map { $0.name })
        for defaultPattern in Self.defaultPatterns {
            if !existingNames.contains(defaultPattern.name) {
                patterns.append(defaultPattern)
            }
        }
        patterns.sort { $0.name.lowercased() < $1.name.lowercased() }
        savePatterns()
        Logger.shared.info("Seeded \(Self.defaultPatterns.count) default workflow patterns")
    }

    // MARK: - Default Patterns

    static let defaultPatterns: [WorkflowPattern] = [
        WorkflowPattern(
            name: "Search Issues",
            trigger: "When the user asks to find, search for, look up, or list issues",
            knowledge: """
            Use the search_issues tool with a JQL query. Build the JQL from the user's request:
            - "my issues" → assignee = currentUser()
            - "open issues" → status != Done AND status != Closed
            - Filter by project, status, assignee, type, sprint, or any Jira field
            - Combine conditions with AND/OR
            - Use ORDER BY for sorting (e.g., ORDER BY created DESC)
            Results will be displayed in the main window.
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Create Issue",
            trigger: "When the user asks to create, make, or add a new issue, ticket, story, bug, or task",
            knowledge: """
            Use the create_issue tool. At minimum, require a project key and summary.
            - Infer the issue type from context (e.g., "bug" → Bug, "story" → Story, default to Task)
            - If the user doesn't specify a project, ask or use the most recently referenced project
            - Set optional fields when mentioned: description, assignee, sprint, epic, components, priority
            - When assigning to "me", use the current user's email
            - After creation, report the new issue key
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Update Issue",
            trigger: "When the user asks to update, change, modify, or set fields on an existing issue",
            knowledge: """
            Use the update_issue tool with the issue key and a fields dictionary.
            - Match the user's intent to Jira field names (e.g., "title" → summary, "description" → description)
            - For assignee changes, use the assign_issue tool instead
            - For status changes, use the change_status tool instead
            - Multiple fields can be updated in a single call
            - When the user says "this issue" or "it", use the currently selected issue(s)
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Change Status",
            trigger: "When the user asks to move, transition, close, reopen, start, or change the status of an issue",
            knowledge: """
            Use the change_status tool with the issue key and the target status name.
            - Map common phrases to statuses: "start" → In Progress, "done"/"close" → Done/Closed, "reopen" → Open/New
            - If unsure which transitions are available, use get_transitions first to see valid options
            - Some transitions may require additional fields — if the transition fails, check available transitions
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Assign Issue",
            trigger: "When the user asks to assign, reassign, or give an issue to someone",
            knowledge: """
            Use the assign_issue tool with the issue key and assignee email.
            - "assign to me" → use the current user's email
            - If the user provides a name rather than email, try to match it
            - Can be combined with other operations in the same request
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Log Work",
            trigger: "When the user asks to log time, record hours, or track work on an issue",
            knowledge: """
            Use the log_work tool with the issue key and time in seconds.
            - Convert time expressions: 1h = 3600, 30m = 1800, 2h30m = 9000, 1d = 28800 (8 hours)
            - If the user says "log 2 hours on SETI-123", that's timeSeconds = 7200
            - Confirm the logged amount in the response
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Add Comment",
            trigger: "When the user asks to comment on, note, or add a comment to an issue",
            knowledge: """
            Use the add_comment tool with the issue key and comment text.
            - Use the user's exact wording for the comment unless they ask you to compose it
            - If the user says "tell them..." or "let them know...", compose a professional comment
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Delete Issue",
            trigger: "When the user asks to delete or remove an issue",
            knowledge: """
            Use the delete_issue tool. This is a destructive operation.
            - Always confirm with the user before deleting
            - Warn that deletion is permanent and cannot be undone
            - If they want to cancel/void an issue instead of deleting, suggest using the Cancel Issue workflow
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Link Issues",
            trigger: "When the user asks to link, connect, or relate two issues, or set a parent/child relationship",
            knowledge: """
            Use the link_issues tool with the source issue key, target issue key, and link type.
            - Common link types: "blocks", "is blocked by", "relates to", "is cloned by", "duplicates"
            - "make X a child of Y" or "set parent to Y" → may need update_issue with parent field instead
            - "X blocks Y" → issueKey=X, linkedIssue=Y, linkType="blocks"
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Add Watcher",
            trigger: "When the user asks to add a watcher, follower, or subscriber to an issue",
            knowledge: """
            Use the add_watcher tool with the issue key and the user's email.
            - "watch this" or "add me as a watcher" → use the current user's email
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Get Issue Transitions",
            trigger: "When the user asks what statuses or transitions are available for an issue",
            knowledge: """
            Use the get_transitions tool to see available status transitions.
            - Show the user the transition names and their target statuses
            - This is useful before attempting a status change to know what's possible
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Get Issue History",
            trigger: "When the user asks about the history, changelog, or changes made to an issue",
            knowledge: """
            Use the fetch_changelog tool to get the change history.
            - Present changes in a readable format: who changed what, when
            - Summarize if the history is long
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Get Project Components",
            trigger: "When the user asks about available components for a project",
            knowledge: """
            Use the get_components tool with the project key.
            - List the available components by name
            - Useful when the user needs to know what components exist before setting one on an issue
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Update Classification",
            trigger: "When the user asks to set or change the request classification on an issue",
            knowledge: """
            Use the update_classification tool with the issue key, parent category value, and optional child sub-category.
            - Classification is a cascading select field with parent and child values
            - If unsure of valid values, ask the user
            """,
            isBuiltIn: true
        ),
        WorkflowPattern(
            name: "Update PCM",
            trigger: "When the user asks to set or change the PCM Master field on an issue",
            knowledge: """
            Use the update_pcm tool with the issue key and the PCM object ID.
            - Pass null/empty to clear the PCM field
            """,
            isBuiltIn: true
        ),
    ]
}
