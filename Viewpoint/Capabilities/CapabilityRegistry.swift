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
    func generateToolsPrompt() -> String {
        var prompt = "## Available Tools\n\n"
        prompt += "You can use the following tools by including a JSON action block in your response:\n\n"

        for capability in capabilities {
            prompt += "### \(capability.name)\n"
            prompt += "\(capability.description)\n\n"

            for tool in capability.tools {
                prompt += "**\(tool.name)**\n"
                prompt += "\(tool.description)\n"
                prompt += "Parameters:\n"

                for param in tool.parameters {
                    let requiredLabel = param.required ? " (required)" : " (optional)"
                    prompt += "- `\(param.name)` (\(param.type.jsonSchemaType))\(requiredLabel): \(param.description)\n"
                }
                prompt += "\n"
            }
        }

        return prompt
    }

    /// Generate example action format for the system prompt
    func generateActionFormatPrompt() -> String {
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
