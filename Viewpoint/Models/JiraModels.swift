import Foundation

// MARK: - Issue Models

struct JiraIssue: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let fields: IssueFields

    var summary: String { fields.summary }
    var status: String { fields.status.name }
    var assignee: String? { fields.assignee?.displayName }
    var issueType: String { fields.issuetype.name }
    var project: String { fields.project.name }
    var epic: String? { fields.customfield_10014 } // Epic link field
    var priority: String? { fields.priority?.name }

    // Helper to create a copy with updated fields
    func withFields(_ newFields: IssueFields) -> JiraIssue {
        JiraIssue(id: id, key: key, fields: newFields)
    }
    var created: Date? {
        guard let dateString = fields.created else { return nil }
        // Try with fractional seconds first, then without
        if let date = JiraIssue.dateFormatterWithFractionalSeconds.date(from: dateString) {
            return date
        }
        if let date = JiraIssue.dateFormatterWithoutFractionalSeconds.date(from: dateString) {
            return date
        }
        // If parsing fails, log it for debugging
        Logger.shared.warning("Failed to parse created date for \(key): '\(dateString)'")
        return nil
    }
    var updated: Date? {
        guard let dateString = fields.updated else { return nil }
        // Try with fractional seconds first, then without
        if let date = JiraIssue.dateFormatterWithFractionalSeconds.date(from: dateString) {
            return date
        }
        if let date = JiraIssue.dateFormatterWithoutFractionalSeconds.date(from: dateString) {
            return date
        }
        // If parsing fails, log it for debugging
        Logger.shared.warning("Failed to parse updated date for \(key): '\(dateString)'")
        return nil
    }

    // Shared date formatters for Jira's ISO8601 format
    private static let dateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct IssueFields: Codable, Hashable {
    let summary: String
    let status: StatusField
    let assignee: UserField?
    let issuetype: IssueTypeField
    let project: ProjectField
    let priority: PriorityField?
    let created: String?
    let updated: String?
    let components: [ComponentField]
    let customfield_10014: String? // Epic Link
    let customfield_10016: Double? // Story Points
    let customfield_10020: [SprintField]? // Sprint
    let timeoriginalestimate: Int? // Original Estimate (seconds)
    let timespent: Int? // Time Logged (seconds)
    let timeestimate: Int? // Time Remaining (seconds)

    // Helper to create a copy with updated sprint
    func withSprint(_ sprint: [SprintField]?) -> IssueFields {
        IssueFields(
            summary: summary,
            status: status,
            assignee: assignee,
            issuetype: issuetype,
            project: project,
            priority: priority,
            created: created,
            updated: updated,
            components: components,
            customfield_10014: customfield_10014,
            customfield_10016: customfield_10016,
            customfield_10020: sprint,
            timeoriginalestimate: timeoriginalestimate,
            timespent: timespent,
            timeestimate: timeestimate
        )
    }

    // Helper to create a copy with updated status
    func withStatus(_ newStatus: StatusField) -> IssueFields {
        IssueFields(
            summary: summary,
            status: newStatus,
            assignee: assignee,
            issuetype: issuetype,
            project: project,
            priority: priority,
            created: created,
            updated: updated,
            components: components,
            customfield_10014: customfield_10014,
            customfield_10016: customfield_10016,
            customfield_10020: customfield_10020,
            timeoriginalestimate: timeoriginalestimate,
            timespent: timespent,
            timeestimate: timeestimate
        )
    }

    init(
        summary: String,
        status: StatusField,
        assignee: UserField?,
        issuetype: IssueTypeField,
        project: ProjectField,
        priority: PriorityField?,
        created: String?,
        updated: String?,
        components: [ComponentField],
        customfield_10014: String?,
        customfield_10016: Double?,
        customfield_10020: [SprintField]?,
        timeoriginalestimate: Int?,
        timespent: Int?,
        timeestimate: Int?
    ) {
        self.summary = summary
        self.status = status
        self.assignee = assignee
        self.issuetype = issuetype
        self.project = project
        self.priority = priority
        self.created = created
        self.updated = updated
        self.components = components
        self.customfield_10014 = customfield_10014
        self.customfield_10016 = customfield_10016
        self.customfield_10020 = customfield_10020
        self.timeoriginalestimate = timeoriginalestimate
        self.timespent = timespent
        self.timeestimate = timeestimate
    }

    // Coding keys to handle optional fields
    enum CodingKeys: String, CodingKey {
        case summary, status, assignee, issuetype, project, priority, created, updated
        case components
        case customfield_10014, customfield_10016, customfield_10020
        case timeoriginalestimate, timespent, timeestimate
    }

    // Default empty array for components
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        status = try container.decode(StatusField.self, forKey: .status)
        assignee = try container.decodeIfPresent(UserField.self, forKey: .assignee)
        issuetype = try container.decode(IssueTypeField.self, forKey: .issuetype)
        project = try container.decode(ProjectField.self, forKey: .project)
        priority = try container.decodeIfPresent(PriorityField.self, forKey: .priority)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        components = (try? container.decode([ComponentField].self, forKey: .components)) ?? []
        customfield_10014 = try container.decodeIfPresent(String.self, forKey: .customfield_10014)
        customfield_10016 = try container.decodeIfPresent(Double.self, forKey: .customfield_10016)
        customfield_10020 = try container.decodeIfPresent([SprintField].self, forKey: .customfield_10020)
        timeoriginalestimate = try container.decodeIfPresent(Int.self, forKey: .timeoriginalestimate)
        timespent = try container.decodeIfPresent(Int.self, forKey: .timespent)
        timeestimate = try container.decodeIfPresent(Int.self, forKey: .timeestimate)
    }
}

struct SprintField: Codable, Hashable {
    let id: Int
    let name: String
    let state: String?
}

struct StatusField: Codable, Hashable {
    let name: String
    let statusCategory: StatusCategory?
}

struct StatusCategory: Codable, Hashable {
    let key: String
    let name: String
}

struct UserField: Codable, Hashable {
    let displayName: String
    let emailAddress: String?
}

struct IssueTypeField: Codable, Hashable {
    let name: String
    let iconUrl: String?
}

struct ProjectField: Codable, Hashable {
    let id: String
    let key: String
    let name: String
}

struct PriorityField: Codable, Hashable {
    let name: String
    let iconUrl: String?
}

struct ComponentField: Codable, Hashable {
    let name: String
}

// MARK: - Sprint Models

struct JiraSprint: Codable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let startDate: String?
    let endDate: String?
    let goal: String?
}

struct SprintInfo {
    let sprint: JiraSprint
    let issues: [JiraIssue]
    var totalIssues: Int { issues.count }
    var completedIssues: Int {
        issues.filter { $0.fields.status.statusCategory?.key == "done" }.count
    }
    var inProgressIssues: Int {
        issues.filter { $0.fields.status.statusCategory?.key == "indeterminate" }.count
    }
    var todoIssues: Int {
        issues.filter { $0.fields.status.statusCategory?.key == "new" }.count
    }
}

// MARK: - API Response Models

struct JiraSearchResponse: Codable {
    let issues: [JiraIssue]
    let total: Int?
    let maxResults: Int?
    let nextPageToken: String?
}

struct JiraSprintResponse: Codable {
    let values: [JiraSprint]
}

struct EpicSummaryResponse: Codable {
    let issues: [EpicSummaryIssue]
}

struct EpicSummaryIssue: Codable {
    let key: String
    let fields: EpicSummaryFields
}

struct EpicSummaryFields: Codable {
    let summary: String
}

// MARK: - Filter Models

struct PersistedFilters: Codable {
    var projects: [String]
    var statuses: [String]
    var assignees: [String]
    var issueTypes: [String]
    var epics: [String]
    var sprints: [Int]
    var showOnlyMyIssues: Bool
}

struct IssueFilters {
    var statuses: Set<String> = []
    var assignees: Set<String> = []
    var issueTypes: Set<String> = []
    var projects: Set<String> = []
    var epics: Set<String> = []
    var sprints: Set<Int> = []
    var startDate: Date?
    var endDate: Date?
    var showOnlyMyIssues: Bool = false

    func buildJQL(userEmail: String) -> String {
        var jqlParts: [String] = []

        // PRIMARY FILTER: Project (if selected, this narrows down everything else)
        if !projects.isEmpty {
            let projectList = projects.map { "\"\($0)\"" }.joined(separator: ", ")
            jqlParts.append("project IN (\(projectList))")
        }

        // SECONDARY FILTER: Assignee
        if !assignees.isEmpty {
            // User has explicitly selected assignees
            let assigneeList = assignees.map { "\"\($0)\"" }.joined(separator: ", ")
            jqlParts.append("assignee IN (\(assigneeList))")
        } else if showOnlyMyIssues {
            // Default: show only my issues
            jqlParts.append("assignee = currentUser()")
        }
        // If assignees is empty and showOnlyMyIssues is false, show all issues

        // OTHER FILTERS (applied after project and assignee)
        if !statuses.isEmpty {
            let statusList = statuses.map { "\"\($0)\"" }.joined(separator: ", ")
            jqlParts.append("status IN (\(statusList))")
        }

        if !issueTypes.isEmpty {
            let typeList = issueTypes.map { "\"\($0)\"" }.joined(separator: ", ")
            jqlParts.append("type IN (\(typeList))")
        }

        if !epics.isEmpty {
            let epicList = epics.map { "\"\($0)\"" }.joined(separator: ", ")
            jqlParts.append("\"Epic Link\" IN (\(epicList))")
        }

        if !sprints.isEmpty {
            let sprintList = sprints.map { String($0) }.joined(separator: ", ")
            jqlParts.append("sprint IN (\(sprintList))")
        }

        if let start = startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            jqlParts.append("created >= \"\(formatter.string(from: start))\"")
        }

        if let end = endDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            jqlParts.append("created <= \"\(formatter.string(from: end))\"")
        }

        // Return a valid JQL query, or a default one if no filters are set
        if jqlParts.isEmpty {
            // Jira Cloud requires at least one search restriction
            // Default to issues created in the last 30 days
            return "created >= -30d order by created DESC"
        }

        return jqlParts.joined(separator: " AND ") + " order by created DESC"
    }
}

// MARK: - Transition Models

struct TransitionInfo {
    let id: String
    let name: String
    let requiredFields: [TransitionField]
}

struct TransitionField {
    let key: String
    let name: String
    let allowedValues: [String]
}

// MARK: - Sorting and Grouping

enum SortOption: String, CaseIterable, Identifiable {
    case status = "Status"
    case dateCreated = "Date Created"
    case dateUpdated = "Date Updated"
    case assignee = "Assignee"
    case epic = "Epic"

    var id: String { rawValue }
}

enum SortDirection: String, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"
}

enum GroupOption: String, CaseIterable, Identifiable {
    case none = "None"
    case assignee = "Assignee"
    case status = "Status"
    case epic = "Epic"
    case initiative = "Initiative"

    var id: String { rawValue }
}

// MARK: - Issue Details Models

struct IssueDetails: Identifiable {
    let id = UUID()
    let issue: JiraIssue
    let description: String?
    let comments: [IssueComment]
    let changelog: String
}

struct IssueComment: Identifiable {
    let id: String
    let author: String
    let created: String
    let body: String
    let parentId: String?
}
