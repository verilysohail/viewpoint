import Foundation

// MARK: - JQL Autocomplete Models

struct JQLSuggestion: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let displayText: String
    let type: SuggestionType
    let description: String?

    enum SuggestionType {
        case field
        case `operator`
        case value
        case keyword
    }

    init(text: String, displayText: String? = nil, type: SuggestionType, description: String? = nil) {
        self.text = text
        self.displayText = displayText ?? text
        self.type = type
        self.description = description
    }
}

// MARK: - JQL Token Context

enum JQLTokenContext {
    case field           // Expecting a field name
    case `operator`      // Expecting an operator
    case value           // Expecting a value
    case conjunction     // Expecting AND/OR/ORDER BY
}

// MARK: - JQL Field Definitions

struct JQLField {
    let name: String
    let aliases: [String]
    let operators: [String]
    let valueType: ValueType
    let description: String

    enum ValueType {
        case text          // Free text
        case list          // Predefined list (projects, statuses, etc.)
        case number        // Numeric
        case date          // Date/time
        case user          // User/assignee
        case function      // Special functions like currentUser()
    }

    static let allFields: [JQLField] = [
        JQLField(name: "project", aliases: [], operators: ["=", "!=", "IN", "NOT IN"], valueType: .list, description: "Project name or key"),
        JQLField(name: "status", aliases: [], operators: ["=", "!=", "IN", "NOT IN", "WAS", "WAS IN", "CHANGED"], valueType: .list, description: "Issue status"),
        JQLField(name: "statusCategory", aliases: [], operators: ["=", "!=", "IN", "NOT IN"], valueType: .list, description: "Status category (To Do, In Progress, Done)"),
        JQLField(name: "assignee", aliases: [], operators: ["=", "!=", "IN", "NOT IN", "WAS", "WAS IN", "CHANGED"], valueType: .user, description: "Issue assignee"),
        JQLField(name: "type", aliases: ["issuetype"], operators: ["=", "!=", "IN", "NOT IN"], valueType: .list, description: "Issue type"),
        JQLField(name: "priority", aliases: [], operators: ["=", "!=", "IN", "NOT IN"], valueType: .list, description: "Issue priority"),
        JQLField(name: "sprint", aliases: [], operators: ["=", "!=", "IN", "NOT IN"], valueType: .number, description: "Sprint ID"),
        JQLField(name: "epic", aliases: ["Epic Link", "customfield_10014"], operators: ["=", "!=", "IN", "NOT IN"], valueType: .text, description: "Epic key"),
        JQLField(name: "created", aliases: [], operators: ["=", "!=", ">", ">=", "<", "<="], valueType: .date, description: "Issue creation date"),
        JQLField(name: "updated", aliases: [], operators: ["=", "!=", ">", ">=", "<", "<="], valueType: .date, description: "Issue last updated date"),
        JQLField(name: "summary", aliases: [], operators: ["~", "!~"], valueType: .text, description: "Issue summary"),
        JQLField(name: "description", aliases: [], operators: ["~", "!~"], valueType: .text, description: "Issue description"),
        JQLField(name: "component", aliases: ["components"], operators: ["=", "!=", "IN", "NOT IN"], valueType: .list, description: "Project component"),
        JQLField(name: "labels", aliases: [], operators: ["=", "!=", "IN", "NOT IN"], valueType: .list, description: "Issue labels"),
    ]

    static func find(name: String) -> JQLField? {
        let lowercaseName = name.lowercased()
        return allFields.first { field in
            field.name.lowercased() == lowercaseName ||
            field.aliases.contains { $0.lowercased() == lowercaseName }
        }
    }
}

// MARK: - JQL Keywords

struct JQLKeyword {
    static let conjunctions = ["AND", "OR"]
    static let orderBy = "ORDER BY"
    static let ascending = "ASC"
    static let descending = "DESC"

    static let specialValues = [
        "EMPTY",
        "NULL",
        "currentUser()",
        "now()",
        "startOfDay()",
        "endOfDay()",
        "startOfWeek()",
        "endOfWeek()",
        "startOfMonth()",
        "endOfMonth()",
    ]

    static let statusCategories = [
        "To Do",
        "In Progress",
        "Done"
    ]
}
