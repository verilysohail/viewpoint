import Foundation

/// Jira capability providing tools for issue management
class JiraCapability: Capability {
    let name = "jira"
    let description = "Tools for managing Jira issues - search, create, update, log work, and more"

    private weak var jiraService: JiraService?

    var tools: [Tool] {
        guard let service = jiraService else { return [] }
        return [
            SearchIssuesTool(jiraService: service),
            CreateIssueTool(jiraService: service),
            UpdateIssueTool(jiraService: service),
            LogWorkTool(jiraService: service),
            ChangeStatusTool(jiraService: service),
            AddCommentTool(jiraService: service),
            AssignIssueTool(jiraService: service),
            GetComponentsTool(jiraService: service),
            UpdateClassificationTool(jiraService: service),
            UpdatePCMTool(jiraService: service),
            DeleteIssueTool(jiraService: service),
            AddWatcherTool(jiraService: service),
            LinkIssuesTool(jiraService: service),
            GetTransitionsTool(jiraService: service),
            FetchChangelogTool(jiraService: service)
        ]
    }

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }
}

// MARK: - Search Issues Tool

class SearchIssuesTool: Tool {
    let name = "search_issues"
    let description = "Search for Jira issues using JQL (Jira Query Language)"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "jql", type: .string, description: "JQL query string (e.g., 'project = SETI AND assignee = currentUser()')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let jql = try stringArgument("jql", from: arguments) else {
            return .failure("JQL query is required")
        }

        await service.searchWithJQL(jql)

        // Get the results from the service
        let issues = await MainActor.run { service.issues }

        return .success("Found \(issues.count) issues", data: issues.map { $0.key })
    }
}

// MARK: - Create Issue Tool

class CreateIssueTool: Tool {
    let name = "create_issue"
    let description = "Create a new Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "project", type: .string, description: "Project key (e.g., 'SETI')"),
        ToolParameter(name: "summary", type: .string, description: "Issue summary/title"),
        ToolParameter(name: "type", type: .string, description: "Issue type (e.g., 'Story', 'Bug', 'Task')", required: false),
        ToolParameter(name: "description", type: .string, description: "Issue description", required: false),
        ToolParameter(name: "assignee", type: .string, description: "Assignee email or account ID", required: false),
        ToolParameter(name: "sprint", type: .string, description: "Sprint name or ID", required: false),
        ToolParameter(name: "epic", type: .string, description: "Epic key or name", required: false),
        ToolParameter(name: "components", type: .array(of: .string), description: "Component names", required: false),
        ToolParameter(name: "priority", type: .string, description: "Priority name", required: false)
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        // Build fields dictionary from arguments
        var fields: [String: Any] = [:]

        if let project = arguments["project"] {
            fields["project"] = project
        }
        if let summary = arguments["summary"] {
            fields["summary"] = summary
        }
        if let type = arguments["type"] {
            fields["type"] = type
        }
        if let description = arguments["description"] {
            fields["description"] = description
        }
        if let assignee = arguments["assignee"] {
            fields["assignee"] = assignee
        }
        if let sprint = arguments["sprint"] {
            fields["sprint"] = sprint
        }
        if let epic = arguments["epic"] {
            fields["epic"] = epic
        }
        if let components = arguments["components"] {
            fields["components"] = components
        }
        if let priority = arguments["priority"] {
            fields["priority"] = priority
        }

        let result = await service.createIssue(fields: fields)

        if result.success, let issueKey = result.issueKey {
            return .success("Created issue \(issueKey)", data: ["issueKey": issueKey])
        } else {
            return .failure("Failed to create issue")
        }
    }
}

// MARK: - Update Issue Tool

class UpdateIssueTool: Tool {
    let name = "update_issue"
    let description = "Update fields on an existing Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "fields", type: .object, description: "Fields to update (e.g., {\"summary\": \"New title\", \"assignee\": \"email@example.com\"})")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let fields = arguments["fields"] as? [String: Any] else {
            return .failure("Fields dictionary is required")
        }

        let success = await service.updateIssue(issueKey: issueKey, fields: fields)

        if success {
            return .success("Updated \(issueKey)")
        } else {
            return .failure("Failed to update \(issueKey)")
        }
    }
}

// MARK: - Log Work Tool

class LogWorkTool: Tool {
    let name = "log_work"
    let description = "Log time spent on a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "timeSeconds", type: .int, description: "Time spent in seconds")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let timeSeconds = try intArgument("timeSeconds", from: arguments) else {
            return .failure("Time in seconds is required")
        }

        let success = await service.logWork(issueKey: issueKey, timeSpentSeconds: timeSeconds)

        if success {
            let hours = Double(timeSeconds) / 3600.0
            return .success("Logged \(String(format: "%.1f", hours)) hours on \(issueKey)")
        } else {
            return .failure("Failed to log work on \(issueKey)")
        }
    }
}

// MARK: - Change Status Tool

class ChangeStatusTool: Tool {
    let name = "change_status"
    let description = "Transition a Jira issue to a new status"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "newStatus", type: .string, description: "Target status name (e.g., 'In Progress', 'Done')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let newStatus = try stringArgument("newStatus", from: arguments) else {
            return .failure("New status is required")
        }

        let success = await service.updateIssueStatus(issueKey: issueKey, newStatus: newStatus)

        if success {
            return .success("Changed \(issueKey) status to '\(newStatus)'")
        } else {
            return .failure("Failed to change status of \(issueKey)")
        }
    }
}

// MARK: - Add Comment Tool

class AddCommentTool: Tool {
    let name = "add_comment"
    let description = "Add a comment to a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "comment", type: .string, description: "Comment text to add")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let comment = try stringArgument("comment", from: arguments) else {
            return .failure("Comment text is required")
        }

        let success = await service.addComment(issueKey: issueKey, comment: comment)

        if success {
            return .success("Added comment to \(issueKey)")
        } else {
            return .failure("Failed to add comment to \(issueKey)")
        }
    }
}

// MARK: - Assign Issue Tool

class AssignIssueTool: Tool {
    let name = "assign_issue"
    let description = "Assign a Jira issue to a user"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "assignee", type: .string, description: "User email or account ID")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let assignee = try stringArgument("assignee", from: arguments) else {
            return .failure("Assignee is required")
        }

        let success = await service.assignIssue(issueKey: issueKey, assigneeEmail: assignee)

        if success {
            return .success("Assigned \(issueKey) to \(assignee)")
        } else {
            return .failure("Failed to assign \(issueKey)")
        }
    }
}

// MARK: - Get Components Tool

class GetComponentsTool: Tool {
    let name = "get_components"
    let description = "Get available components for a Jira project"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "projectKey", type: .string, description: "Project key (e.g., 'SETI')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let projectKey = try stringArgument("projectKey", from: arguments) else {
            return .failure("Project key is required")
        }

        let result = await service.fetchProjectComponents(projectKey: projectKey)

        if !result.success {
            return .failure("Failed to fetch components for \(projectKey)")
        }

        if result.components.isEmpty {
            return .success("No components found for \(projectKey)", data: [])
        } else {
            let componentNames = result.components.map { $0.name }
            return .success("Found \(result.components.count) components", data: componentNames)
        }
    }
}

// MARK: - Update Classification Tool

class UpdateClassificationTool: Tool {
    let name = "update_classification"
    let description = "Update the Request Classification field on a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "parentValue", type: .string, description: "Parent category value"),
        ToolParameter(name: "childValue", type: .string, description: "Child sub-category value", required: false)
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let parentValue = try stringArgument("parentValue", from: arguments) else {
            return .failure("Parent value is required")
        }

        let childValue = try stringArgument("childValue", from: arguments, required: false)

        let success = await service.updateRequestClassification(
            issueKey: issueKey,
            parentValue: parentValue,
            childValue: childValue
        )

        if success {
            if let child = childValue {
                return .success("Set classification to '\(parentValue) -> \(child)' on \(issueKey)")
            } else {
                return .success("Set classification to '\(parentValue)' on \(issueKey)")
            }
        } else {
            return .failure("Failed to update classification on \(issueKey)")
        }
    }
}

// MARK: - Update PCM Tool

class UpdatePCMTool: Tool {
    let name = "update_pcm"
    let description = "Update the PCM Master field on a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "objectId", type: .string, description: "PCM object ID (or null to clear)")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        let objectId = try stringArgument("objectId", from: arguments, required: false)

        let success = await service.updatePCMMaster(issueKey: issueKey, objectId: objectId)

        if success {
            if let objId = objectId {
                return .success("Updated PCM on \(issueKey) to object \(objId)")
            } else {
                return .success("Cleared PCM on \(issueKey)")
            }
        } else {
            return .failure("Failed to update PCM on \(issueKey)")
        }
    }
}

// MARK: - Delete Issue Tool

class DeleteIssueTool: Tool {
    let name = "delete_issue"
    let description = "Delete a Jira issue (use with caution)"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        let success = await service.deleteIssue(issueKey: issueKey)

        if success {
            return .success("Deleted \(issueKey)")
        } else {
            return .failure("Failed to delete \(issueKey)")
        }
    }
}

// MARK: - Add Watcher Tool

class AddWatcherTool: Tool {
    let name = "add_watcher"
    let description = "Add a user as a watcher on a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "watcher", type: .string, description: "User email or account ID to add as watcher")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let watcher = try stringArgument("watcher", from: arguments) else {
            return .failure("Watcher is required")
        }

        let success = await service.addWatcher(issueKey: issueKey, watcherEmail: watcher)

        if success {
            return .success("Added \(watcher) as watcher on \(issueKey)")
        } else {
            return .failure("Failed to add watcher to \(issueKey)")
        }
    }
}

// MARK: - Link Issues Tool

class LinkIssuesTool: Tool {
    let name = "link_issues"
    let description = "Create a link between two Jira issues"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Source issue key (e.g., 'SETI-123')"),
        ToolParameter(name: "linkedIssue", type: .string, description: "Target issue key to link to"),
        ToolParameter(name: "linkType", type: .string, description: "Link type (e.g., 'blocks', 'is blocked by', 'relates to')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        guard let linkedIssue = try stringArgument("linkedIssue", from: arguments) else {
            return .failure("Linked issue key is required")
        }

        guard let linkType = try stringArgument("linkType", from: arguments) else {
            return .failure("Link type is required")
        }

        let success = await service.linkIssues(
            issueKey: issueKey,
            linkedIssueKey: linkedIssue,
            linkType: linkType
        )

        if success {
            return .success("Linked \(issueKey) to \(linkedIssue) with '\(linkType)'")
        } else {
            return .failure("Failed to link issues")
        }
    }
}

// MARK: - Get Transitions Tool

class GetTransitionsTool: Tool {
    let name = "get_transitions"
    let description = "Get available status transitions for a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        let transitions = await service.fetchTransitions(forIssue: issueKey)

        if transitions.isEmpty {
            return .success("No transitions available for \(issueKey)", data: [])
        } else {
            // Format transitions showing both name and target status
            let transitionInfo = transitions.map { "\($0.name) -> \($0.targetStatus)" }
            return .success("Available transitions: \(transitionInfo.joined(separator: ", "))", data: transitionInfo)
        }
    }
}

// MARK: - Fetch Changelog Tool

class FetchChangelogTool: Tool {
    let name = "fetch_changelog"
    let description = "Get the change history for a Jira issue"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "issueKey", type: .string, description: "Issue key (e.g., 'SETI-123')")
    ]

    private weak var jiraService: JiraService?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let service = jiraService else {
            return .failure("JiraService not available")
        }

        guard let issueKey = try stringArgument("issueKey", from: arguments) else {
            return .failure("Issue key is required")
        }

        let result = await service.fetchChangelog(issueKey: issueKey)

        if result.success, let changelog = result.changelog {
            return .success("Changelog for \(issueKey)", data: changelog)
        } else {
            return .failure("Failed to fetch changelog for \(issueKey)")
        }
    }
}
