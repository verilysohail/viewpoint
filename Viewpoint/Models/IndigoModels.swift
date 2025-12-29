import Foundation

// MARK: - Message Models

struct Message: Identifiable, Equatable {
    let id: UUID
    let text: String
    let sender: Sender
    let timestamp: Date
    let status: MessageStatus?

    init(id: UUID = UUID(), text: String, sender: Sender, timestamp: Date = Date(), status: MessageStatus? = nil) {
        self.id = id
        self.text = text
        self.sender = sender
        self.timestamp = timestamp
        self.status = status
    }

    enum Sender: Equatable {
        case user
        case ai
        case system
    }

    enum MessageStatus: Equatable {
        case success
        case warning
        case error
        case processing
    }
}

// MARK: - AI Models

enum AIModel: String, CaseIterable, Identifiable {
    case gemini3ProPreview = "gemini-3-pro-preview"
    case gemini25Pro = "gemini-2.5-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini3ProPreview:
            return "Gemini 3 Pro Preview (Best Quality)"
        case .gemini25Pro:
            return "Gemini 2.5 Pro (Fast & Efficient)"
        }
    }

    // Some models are only available in the global region
    var usesGlobalRegion: Bool {
        switch self {
        case .gemini3ProPreview: return true
        case .gemini25Pro: return false
        }
    }

    var inputCostPer1M: Double {
        switch self {
        case .gemini3ProPreview: return 1.25
        case .gemini25Pro: return 1.25
        }
    }

    var outputCostPer1M: Double {
        switch self {
        case .gemini3ProPreview: return 5.00
        case .gemini25Pro: return 5.00
        }
    }
}

// MARK: - AI Context

struct AIContext {
    let currentUser: String
    let selectedIssues: [JiraIssue]
    let selectedIssueDetails: [IssueDetails]  // Full details for selected issues (description, comments, etc.)
    let currentFilters: IssueFilters
    let visibleIssues: [JiraIssue]
    let availableProjects: [String]
    let availableSprints: [JiraSprint]
    let availableEpics: [String]
    let availableStatuses: [String]
    let availableResolutions: [String]
    let lastSearchResults: [JiraIssue]?
    let lastCreatedIssue: String?
}

// MARK: - AI Action (New JSON-based action system)

/// Represents a single action to be executed by the capability system
struct AIAction: Codable, Equatable {
    let tool: String
    let args: [String: AnyCodableValue]

    init(tool: String, args: [String: Any]) {
        self.tool = tool
        self.args = args.mapValues { AnyCodableValue($0) }
    }

    /// Convert args back to [String: Any] for tool execution
    var arguments: [String: Any] {
        return args.mapValues { $0.value }
    }
}

/// A type-erased Codable value for handling dynamic JSON
struct AnyCodableValue: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableValue($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodableValue($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            // Try to encode as string representation
            try container.encode(String(describing: value))
        }
    }

    static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
        // Simple equality check based on string representation
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - AI Response

struct AIResponse {
    let text: String
    let actions: [AIAction]  // New: JSON-based actions
    let intents: [Intent]    // Legacy: Keep for backwards compatibility during migration
    let inputTokens: Int
    let outputTokens: Int

    /// Initialize with actions (new system)
    init(text: String, actions: [AIAction], inputTokens: Int, outputTokens: Int) {
        self.text = text
        self.actions = actions
        self.intents = []  // No legacy intents
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// Initialize with legacy intents (backwards compatibility)
    init(text: String, intents: [Intent], inputTokens: Int, outputTokens: Int) {
        self.text = text
        self.actions = []  // No new actions
        self.intents = intents
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum Intent {
        case search(jql: String)
        case update(issueKey: String, fields: [String: Any])
        case create(fields: [String: Any])
        case logWork(issueKey: String, timeSeconds: Int)
        case changeStatus(issueKey: String, newStatus: String)
        case addComment(issueKey: String, comment: String)
        case deleteIssue(issueKey: String)
        case assignIssue(issueKey: String, assignee: String)
        case addWatcher(issueKey: String, watcher: String)
        case linkIssues(issueKey: String, linkedIssue: String, linkType: String)
        case fetchChangelog(issueKey: String)
        case showIssueDetail(issueKey: String)
        case getTransitions(issueKey: String)
        case sprintLookup(query: String, projectKey: String?)
        case componentLookup(projectKey: String)
        case classificationLookup(issueKey: String, query: String)
        case classificationSelect(issueKey: String, optionIndex: Int)
        case pcmLookup(issueKey: String, query: String)
        case pcmSelect(issueKey: String, optionIndex: Int)
    }

    var estimatedCost: Double {
        // Will be calculated based on model
        return 0.0
    }
}
