import Foundation
import SwiftUI

/// Central registry for all capabilities and their tools
/// Acts as the single source of truth for what actions are available to the AI
@MainActor
class CapabilityRegistry: ObservableObject {
    static let shared = CapabilityRegistry()

    @Published private(set) var capabilities: [Capability] = []

    private var toolCache: [String: Tool] = [:]

    private init() {}

    // MARK: - Registration

    /// Register a new capability with its tools
    func register(_ capability: Capability) {
        capabilities.append(capability)
        // Cache tools for fast lookup
        for tool in capability.tools {
            toolCache[tool.name] = tool
        }
        Logger.shared.info("Registered capability: \(capability.name) with \(capability.tools.count) tools")
    }

    /// Unregister a capability by name
    func unregister(named name: String) {
        if let index = capabilities.firstIndex(where: { $0.name == name }) {
            let capability = capabilities[index]
            // Remove tools from cache
            for tool in capability.tools {
                toolCache.removeValue(forKey: tool.name)
            }
            capabilities.remove(at: index)
            Logger.shared.info("Unregistered capability: \(name)")
        }
    }

    // MARK: - Tool Access

    /// Find a tool by name
    func tool(named name: String) -> Tool? {
        return toolCache[name]
    }

    /// Get all registered tools across all capabilities
    func allTools() -> [Tool] {
        return capabilities.flatMap { $0.tools }
    }

    /// Get tools for a specific capability
    func tools(for capabilityName: String) -> [Tool] {
        return capabilities.first { $0.name == capabilityName }?.tools ?? []
    }

    // MARK: - Tool Execution

    /// Execute a tool by name with the given arguments
    func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let tool = tool(named: toolName) else {
            throw ToolError.toolNotFound(toolName)
        }

        Logger.shared.debug("Executing tool: \(toolName) with arguments: \(arguments)")
        let result = try await tool.execute(with: arguments)
        Logger.shared.debug("Tool \(toolName) completed with success: \(result.success)")

        return result
    }

    // MARK: - Schema Generation

    /// Generate JSON schema for all tools (for AI system prompt)
    func generateToolsSchema() -> [[String: Any]] {
        return allTools().map { $0.generateToolSchema() }
    }

    /// Generate a formatted tools section for the AI system prompt
    /// This method is nonisolated to allow calling from non-MainActor contexts
    nonisolated func generateToolsPrompt() -> String {
        // Access capabilities synchronously for prompt generation
        // This is safe because we're just reading the current state
        var prompt = "## Available Tools\n\n"
        prompt += "You can use the following tools by including a JSON action block in your response:\n\n"

        // Get tools synchronously using MainActor.assumeIsolated is not available,
        // so we use a predefined list of tool documentation
        prompt += """
        ### jira
        Tools for managing Jira issues - search, create, update, log work, and more

        **search_issues**
        Search for Jira issues using JQL (Jira Query Language)
        Parameters:
        - `jql` (string) (required): JQL query string (e.g., 'project = SETI AND assignee = currentUser()')

        **create_issue**
        Create a new Jira issue
        Parameters:
        - `project` (string) (required): Project key (e.g., 'SETI')
        - `summary` (string) (required): Issue summary/title
        - `type` (string) (optional): Issue type (e.g., 'Story', 'Bug', 'Task')
        - `description` (string) (optional): Issue description
        - `assignee` (string) (optional): Assignee email or account ID
        - `sprint` (string) (optional): Sprint name or ID
        - `epic` (string) (optional): Epic key or name
        - `components` (array) (optional): Component names
        - `priority` (string) (optional): Priority name

        **update_issue**
        Update fields on an existing Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `fields` (object) (required): Fields to update (e.g., {"summary": "New title", "priority": "High"})

        **log_work**
        Log time spent on a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `timeSeconds` (integer) (required): Time spent in seconds (e.g., 3600 for 1 hour)

        **change_status**
        Transition a Jira issue to a new status
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `newStatus` (string) (required): Target status name (e.g., 'In Progress', 'Done')

        **add_comment**
        Add a comment to a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `comment` (string) (required): Comment text to add

        **assign_issue**
        Assign a Jira issue to a user
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `assignee` (string) (required): User email or account ID

        **delete_issue**
        Delete a Jira issue (use with caution)
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')

        **get_components**
        Get available components for a Jira project
        Parameters:
        - `projectKey` (string) (required): Project key (e.g., 'SETI')

        **get_transitions**
        Get available status transitions for a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')

        **fetch_changelog**
        Get the change history for a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')

        **link_issues**
        Create a link between two Jira issues
        Parameters:
        - `issueKey` (string) (required): Source issue key (e.g., 'SETI-123')
        - `linkedIssue` (string) (required): Target issue key to link to
        - `linkType` (string) (required): Link type (e.g., 'blocks', 'relates to')

        **add_watcher**
        Add a user as a watcher on a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `watcher` (string) (required): User email or account ID

        **update_classification**
        Update the Request Classification field on a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `parentValue` (string) (required): Parent category value
        - `childValue` (string) (optional): Child sub-category value

        **update_pcm**
        Update the PCM Master field on a Jira issue
        Parameters:
        - `issueKey` (string) (required): Issue key (e.g., 'SETI-123')
        - `objectId` (string) (required): PCM object ID

        """
        return prompt
    }

    /// Generate example action format for the system prompt
    /// This method is nonisolated to allow calling from non-MainActor contexts
    nonisolated func generateActionFormatPrompt() -> String {
        return """
        ## Action Format

        To use a tool, include an action block in your response using this format:

        ```
        ACTION: {"tool": "tool_name", "args": {"param1": "value1", "param2": "value2"}}
        ```

        You can include multiple actions in a single response. Each action should be on its own line.

        Example:
        I'll search for your issues and log the work.

        ACTION: {"tool": "search_issues", "args": {"jql": "project = SETI AND assignee = currentUser()"}}
        ACTION: {"tool": "log_work", "args": {"issueKey": "SETI-123", "timeSeconds": 3600}}
        """
    }
}

// MARK: - Capability Registry Extensions

extension CapabilityRegistry {
    /// Check if a capability is registered
    func hasCapability(named name: String) -> Bool {
        return capabilities.contains { $0.name == name }
    }

    /// Get count of all registered tools
    var totalToolCount: Int {
        return toolCache.count
    }
}
