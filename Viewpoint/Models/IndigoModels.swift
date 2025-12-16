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

// MARK: - AI Response

struct AIResponse {
    let text: String
    let intents: [Intent]
    let inputTokens: Int
    let outputTokens: Int

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
    }

    var estimatedCost: Double {
        // Will be calculated based on model
        return 0.0
    }
}
