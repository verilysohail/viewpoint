import Foundation

// MARK: - Tool Protocol

/// A tool represents a single action that can be executed by an AI agent
protocol Tool {
    /// Unique identifier for the tool (e.g., "search_issues", "create_issue")
    var name: String { get }

    /// Human-readable description of what the tool does
    var description: String { get }

    /// Parameters accepted by this tool
    var parameters: [ToolParameter] { get }

    /// Execute the tool with the given arguments
    /// - Parameter arguments: Dictionary of argument name to value
    /// - Returns: Result of the tool execution
    func execute(with arguments: [String: Any]) async throws -> ToolResult
}

// MARK: - Tool Parameter

/// Describes a parameter accepted by a tool
struct ToolParameter: Equatable {
    let name: String
    let type: ParameterType
    let description: String
    let required: Bool

    init(name: String, type: ParameterType, description: String, required: Bool = true) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }

    /// Convert to JSON schema format for AI system prompt
    func toJSONSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "type": type.jsonSchemaType,
            "description": description
        ]
        if let items = type.jsonSchemaItems {
            schema["items"] = items
        }
        return schema
    }
}

/// Parameter types supported by tools
indirect enum ParameterType: Equatable {
    case string
    case int
    case double
    case bool
    case array(of: ParameterType)
    case object

    var jsonSchemaType: String {
        switch self {
        case .string: return "string"
        case .int: return "integer"
        case .double: return "number"
        case .bool: return "boolean"
        case .array: return "array"
        case .object: return "object"
        }
    }

    var jsonSchemaItems: [String: Any]? {
        switch self {
        case .array(let itemType):
            return ["type": itemType.jsonSchemaType]
        default:
            return nil
        }
    }
}

// MARK: - Tool Result

/// Result of executing a tool
struct ToolResult {
    let success: Bool
    let data: Any?
    let message: String?

    static func success(_ message: String? = nil, data: Any? = nil) -> ToolResult {
        ToolResult(success: true, data: data, message: message)
    }

    static func failure(_ message: String) -> ToolResult {
        ToolResult(success: false, data: nil, message: message)
    }
}

// MARK: - Tool Errors

enum ToolError: Error, LocalizedError {
    case missingRequiredParameter(String)
    case invalidParameterType(parameter: String, expected: String, got: String)
    case executionFailed(String)
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameterType(let parameter, let expected, let got):
            return "Invalid type for parameter '\(parameter)': expected \(expected), got \(got)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}

// MARK: - Capability Protocol

/// A capability represents a group of related tools (e.g., "Jira", "Calendar")
protocol Capability {
    /// Unique identifier for the capability
    var name: String { get }

    /// Human-readable description of what this capability provides
    var description: String { get }

    /// All tools provided by this capability
    var tools: [Tool] { get }
}

// MARK: - Tool Extensions

extension Tool {
    /// Validate that all required parameters are present
    func validateArguments(_ arguments: [String: Any]) throws {
        for param in parameters where param.required {
            guard arguments[param.name] != nil else {
                throw ToolError.missingRequiredParameter(param.name)
            }
        }
    }

    /// Get a string argument, throwing if missing or wrong type when required
    func stringArgument(_ name: String, from arguments: [String: Any], required: Bool = true) throws -> String? {
        guard let value = arguments[name] else {
            if required {
                throw ToolError.missingRequiredParameter(name)
            }
            return nil
        }
        guard let stringValue = value as? String else {
            throw ToolError.invalidParameterType(parameter: name, expected: "string", got: String(describing: type(of: value)))
        }
        return stringValue
    }

    /// Get an integer argument, throwing if missing or wrong type when required
    func intArgument(_ name: String, from arguments: [String: Any], required: Bool = true) throws -> Int? {
        guard let value = arguments[name] else {
            if required {
                throw ToolError.missingRequiredParameter(name)
            }
            return nil
        }
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }
        throw ToolError.invalidParameterType(parameter: name, expected: "integer", got: String(describing: type(of: value)))
    }

    /// Get a boolean argument, throwing if missing or wrong type when required
    func boolArgument(_ name: String, from arguments: [String: Any], required: Bool = true) throws -> Bool? {
        guard let value = arguments[name] else {
            if required {
                throw ToolError.missingRequiredParameter(name)
            }
            return nil
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let stringValue = value as? String {
            return stringValue.lowercased() == "true"
        }
        throw ToolError.invalidParameterType(parameter: name, expected: "boolean", got: String(describing: type(of: value)))
    }

    /// Generate JSON schema for this tool's parameters
    func generateParameterSchema() -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for param in parameters {
            properties[param.name] = param.toJSONSchema()
            if param.required {
                required.append(param.name)
            }
        }

        return [
            "type": "object",
            "properties": properties,
            "required": required
        ]
    }

    /// Generate complete tool schema for AI system prompt
    func generateToolSchema() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "parameters": generateParameterSchema()
        ]
    }
}
