import Foundation
import Combine

class JiraService: ObservableObject {
    @Published var issues: [JiraIssue] = []
    @Published var sprints: [JiraSprint] = []
    @Published var currentSprintInfo: SprintInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var totalIssuesAvailable: Int = 0
    @Published var hasMoreIssues: Bool = false

    private let config = Configuration.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentStartAt: Int = 0

    // User-configurable initial load count
    private var initialLoadCount: Int {
        UserDefaults.standard.integer(forKey: "initialLoadCount") == 0 ? 100 : UserDefaults.standard.integer(forKey: "initialLoadCount")
    }

    // Available filter options (populated from current issue results)
    @Published var availableStatuses: Set<String> = []
    @Published var availableAssignees: Set<String> = []
    @Published var availableIssueTypes: Set<String> = []
    @Published var availableProjects: Set<String> = []
    @Published var availableEpics: Set<String> = []
    @Published var availableSprints: [JiraSprint] = []

    // Epic summaries (epic key -> summary)
    @Published var epicSummaries: [String: String] = [:]

    // Current filters
    @Published var filters = IssueFilters()

    init() {
        loadPersistedFilters()
        loadInitialData()
    }

    private func loadPersistedFilters() {
        if let data = UserDefaults.standard.data(forKey: "savedFilters"),
           let decoded = try? JSONDecoder().decode(PersistedFilters.self, from: data) {
            filters.projects = Set(decoded.projects)
            filters.statuses = Set(decoded.statuses)
            filters.assignees = Set(decoded.assignees)
            filters.issueTypes = Set(decoded.issueTypes)
            filters.epics = Set(decoded.epics)
            filters.sprints = Set(decoded.sprints)
            filters.showOnlyMyIssues = decoded.showOnlyMyIssues
            Logger.shared.info("Loaded persisted filters: \(filters)")
        }
    }

    func saveFilters() {
        let persisted = PersistedFilters(
            projects: Array(filters.projects),
            statuses: Array(filters.statuses),
            assignees: Array(filters.assignees),
            issueTypes: Array(filters.issueTypes),
            epics: Array(filters.epics),
            sprints: Array(filters.sprints),
            showOnlyMyIssues: filters.showOnlyMyIssues
        )
        if let encoded = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(encoded, forKey: "savedFilters")
            Logger.shared.info("Saved filters: \(filters)")
        }
    }

    func loadInitialData() {
        Task {
            await fetchMyIssues()
            // Note: Sprints are now populated from issue data in updateAvailableFilters()
            // No need to fetch all sprints from all boards
        }
    }

    func refresh() {
        loadInitialData()
    }

    // MARK: - API Requests

    private func createRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let credentials = "\(config.jiraEmail):\(config.jiraAPIKey)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func fetchMyIssues(updateAvailableOptions: Bool = true) async {
        // Reset pagination state when fetching fresh
        await MainActor.run {
            isLoading = true
            currentStartAt = 0
            issues = []
        }

        await loadMoreIssues(updateAvailableOptions: updateAvailableOptions, initialFetchLimit: initialLoadCount)
    }

    func loadMoreIssues(updateAvailableOptions: Bool = false, initialFetchLimit: Int = 500) async {
        await MainActor.run { isLoading = true }

        let jql = filters.buildJQL(userEmail: config.jiraEmail)

        let maxResults = 100
        let currentStart = await MainActor.run { currentStartAt }
        var allIssues: [JiraIssue] = await MainActor.run { issues }
        var startAt = currentStart
        let fetchLimit = currentStart == 0 ? initialFetchLimit : 500 // Initial fetch or subsequent "Load more"
        var total = 0

        do {
            Logger.shared.info("JQL: \(jql)")
            Logger.shared.info("Starting at: \(startAt), will fetch up to \(fetchLimit) more issues")

            var fetchedInThisBatch = 0
            var lastFetchWasFull = true

            repeat {
                // Build URL with query parameters for the new /search/jql endpoint
                var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
                components.queryItems = [
                    URLQueryItem(name: "jql", value: jql),
                    URLQueryItem(name: "startAt", value: String(startAt)),
                    URLQueryItem(name: "maxResults", value: String(maxResults)),
                    URLQueryItem(name: "fields", value: "summary,status,assignee,issuetype,project,priority,created,updated,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
                ]

                guard let url = components.url else {
                    await MainActor.run {
                        errorMessage = "Invalid URL"
                        isLoading = false
                    }
                    return
                }

                Logger.shared.info("Fetching issues from: \(url)")

                // Create GET request
                let request = createRequest(url: url)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                Logger.shared.info("Response status: \(httpResponse.statusCode) (fetching batch starting at \(startAt))")

                if httpResponse.statusCode != 200 {
                    // Try to parse error message from response
                    if let errorMessage = String(data: data, encoding: .utf8) {
                        Logger.shared.error("Error response (\(httpResponse.statusCode)): \(errorMessage)")
                    }
                    throw NSError(domain: "JiraAPI", code: httpResponse.statusCode,
                                 userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }

                let searchResponse = try JSONDecoder().decode(JiraSearchResponse.self, from: data)

                // The new /search/jql API doesn't return a total field, so we need to infer if there are more issues
                // by checking if we got a full page of results
                allIssues.append(contentsOf: searchResponse.issues)
                startAt += searchResponse.issues.count
                fetchedInThisBatch += searchResponse.issues.count

                // If we got fewer issues than requested, we've reached the end
                lastFetchWasFull = searchResponse.issues.count >= maxResults

                Logger.shared.info("Fetched \(searchResponse.issues.count) issues (loaded so far: \(allIssues.count), got full page: \(lastFetchWasFull))")

            } while fetchedInThisBatch < fetchLimit && lastFetchWasFull

            // Since the API doesn't provide total, we estimate based on whether the last fetch was a full page
            // If it was a full page, there might be more; otherwise, we've got everything
            total = lastFetchWasFull ? allIssues.count + 1 : allIssues.count // +1 to indicate there might be more

            Logger.shared.info("Successfully fetched \(allIssues.count) of \(total) total issues")

            await MainActor.run {
                self.issues = allIssues
                self.totalIssuesAvailable = total
                self.hasMoreIssues = allIssues.count < total
                self.currentStartAt = startAt
                if updateAvailableOptions {
                    self.updateAvailableFilters()
                }
                self.isLoading = false
                self.errorMessage = nil
            }

            // Fetch epic summaries for all epics in the result set (only on initial fetch)
            if currentStart == 0 {
                await fetchEpicSummaries()
            }
        } catch {
            Logger.shared.error("Error fetching issues: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to fetch issues: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func fetchSprints() async {
        let urlString = "\(config.jiraBaseURL)/rest/agile/1.0/board"

        guard let url = URL(string: urlString) else { return }

        let request = createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Parse boards and fetch sprints from ALL boards
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let values = json["values"] as? [[String: Any]] {

                Logger.shared.info("Found \(values.count) boards")

                // Fetch sprints from all boards concurrently
                var allSprints: [JiraSprint] = []

                for board in values {
                    if let boardId = board["id"] as? Int {
                        let boardSprints = await fetchSprintsForBoard(boardId: boardId)
                        allSprints.append(contentsOf: boardSprints)
                    }
                }

                // Remove duplicates based on sprint ID
                let uniqueSprints = Dictionary(grouping: allSprints, by: { $0.id })
                    .compactMap { $0.value.first }
                    .sorted { $0.id > $1.id } // Most recent first

                await MainActor.run {
                    self.sprints = uniqueSprints
                    if let activeSprint = uniqueSprints.first(where: { $0.state == "active" }) {
                        Task {
                            await self.fetchSprintInfo(sprintId: activeSprint.id)
                        }
                    }
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch boards: \(error)")
        }
    }

    private func fetchSprintsForBoard(boardId: Int) async -> [JiraSprint] {
        let urlString = "\(config.jiraBaseURL)/rest/agile/1.0/board/\(boardId)/sprint?state=active,future,closed"

        guard let url = URL(string: urlString) else { return [] }

        let request = createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let sprintResponse = try JSONDecoder().decode(JiraSprintResponse.self, from: data)
            Logger.shared.info("Board \(boardId) has \(sprintResponse.values.count) sprints")
            return sprintResponse.values
        } catch {
            Logger.shared.error("Failed to fetch sprints for board \(boardId): \(error)")
            return []
        }
    }

    func fetchSprintInfo(sprintId: Int) async {
        let jql = "sprint = \(sprintId)"

        // Build URL with query parameters for the new /search/jql endpoint
        var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "summary,status,assignee,issuetype,project,priority,created,updated,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
        ]

        guard let url = components.url else {
            return
        }

        // Create GET request
        let request = createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let searchResponse = try JSONDecoder().decode(JiraSearchResponse.self, from: data)

            if let sprint = sprints.first(where: { $0.id == sprintId }) {
                await MainActor.run {
                    self.currentSprintInfo = SprintInfo(sprint: sprint, issues: searchResponse.issues)
                }
            }
        } catch {
            print("Failed to fetch sprint info: \(error)")
        }
    }

    func fetchEpicSummaries() async {
        // Collect all unique epic keys from current issues
        let epicKeys = Set(issues.compactMap { $0.fields.customfield_10014 })

        guard !epicKeys.isEmpty else {
            return
        }

        // Build JQL to fetch all these epics
        let epicKeysArray = Array(epicKeys)
        let jql = "key in (\(epicKeysArray.map { "\"\($0)\"" }.joined(separator: ", ")))"

        // Build URL with query parameters for the new /search/jql endpoint
        var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: String(epicKeys.count)),
            URLQueryItem(name: "fields", value: "summary")
        ]

        guard let url = components.url else {
            return
        }

        // Create GET request
        let request = createRequest(url: url)

        do {

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    if let errorMsg = String(data: data, encoding: .utf8) {
                        Logger.shared.error("Epic fetch error: \(errorMsg)")
                    }
                    return
                }
            }

            let searchResponse = try JSONDecoder().decode(EpicSummaryResponse.self, from: data)
            let summaries = Dictionary(uniqueKeysWithValues: searchResponse.issues.map { ($0.key, $0.fields.summary) })

            await MainActor.run {
                self.epicSummaries = summaries
            }
        } catch {
            Logger.shared.error("Failed to fetch epic summaries: \(error)")
        }
    }

    private func updateAvailableFilters() {
        availableStatuses = Set(issues.map { $0.status })
        availableAssignees = Set(issues.compactMap { $0.assignee })
        availableIssueTypes = Set(issues.map { $0.issueType })
        availableProjects = Set(issues.map { $0.project })
        availableEpics = Set(issues.compactMap { $0.epic })

        // Extract unique sprints from issues
        var sprintMap: [Int: JiraSprint] = [:]
        for issue in issues {
            if let sprints = issue.fields.customfield_10020 {
                for sprintField in sprints {
                    if sprintMap[sprintField.id] == nil {
                        sprintMap[sprintField.id] = JiraSprint(
                            id: sprintField.id,
                            name: sprintField.name,
                            state: sprintField.state ?? "unknown",
                            startDate: nil,
                            endDate: nil,
                            goal: nil
                        )
                    }
                }
            }
        }
        availableSprints = sprintMap.values.sorted { $0.id > $1.id } // Most recent first
    }

    func applyFilters() {
        saveFilters()
        Task {
            // Don't update available filter options when applying filters
            // This keeps all original options visible for multi-select
            await fetchMyIssues(updateAvailableOptions: false)
        }
    }

    func getTransitionInfo(issueKey: String, targetStatus: String) async -> TransitionInfo? {
        let transitionsURL = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/transitions"

        guard let url = URL(string: transitionsURL) else {
            print("Invalid URL for getting transitions")
            return nil
        }

        let request = createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let transitions = json["transitions"] as? [[String: Any]] {

                // Find the transition that matches the desired status
                if let transition = transitions.first(where: { trans in
                    if let to = trans["to"] as? [String: Any],
                       let name = to["name"] as? String {
                        return name.lowercased() == targetStatus.lowercased()
                    }
                    return false
                }),
                   let transitionId = transition["id"] as? String,
                   let transitionName = transition["name"] as? String {

                    // Parse required fields
                    var requiredFields: [TransitionField] = []

                    if let fields = transition["fields"] as? [String: Any] {
                        for (fieldKey, fieldValue) in fields {
                            if let fieldDict = fieldValue as? [String: Any],
                               let required = fieldDict["required"] as? Bool,
                               required {

                                let fieldName = fieldDict["name"] as? String ?? fieldKey
                                var allowedValues: [String] = []

                                // Parse allowed values for the field
                                if let allowedValuesArray = fieldDict["allowedValues"] as? [[String: Any]] {
                                    allowedValues = allowedValuesArray.compactMap { $0["name"] as? String }
                                }

                                requiredFields.append(TransitionField(
                                    key: fieldKey,
                                    name: fieldName,
                                    allowedValues: allowedValues
                                ))
                            }
                        }
                    }

                    return TransitionInfo(id: transitionId, name: transitionName, requiredFields: requiredFields)
                }
            }

            return nil
        } catch {
            print("Failed to get transition info: \(error)")
            return nil
        }
    }

    func updateIssueStatus(issueKey: String, newStatus: String, fieldValues: [String: String] = [:]) async -> Bool {
        // First, get available transitions for this issue
        let transitionsURL = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/transitions"

        guard let url = URL(string: transitionsURL) else {
            print("Invalid URL for getting transitions")
            return false
        }

        let request = createRequest(url: url)

        do {
            // Get available transitions
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let transitions = json["transitions"] as? [[String: Any]] {

                // Find the transition that matches the desired status
                if let transition = transitions.first(where: { trans in
                    if let to = trans["to"] as? [String: Any],
                       let name = to["name"] as? String {
                        return name.lowercased() == newStatus.lowercased()
                    }
                    return false
                }),
                   let transitionId = transition["id"] as? String {

                    // Execute the transition
                    var transitionRequest = createRequest(url: url)
                    transitionRequest.httpMethod = "POST"

                    var requestBody: [String: Any] = [
                        "transition": ["id": transitionId]
                    ]

                    // Add field values if provided
                    if !fieldValues.isEmpty {
                        var fields: [String: Any] = [:]
                        for (key, value) in fieldValues {
                            // Resolution field needs to be in a specific format
                            if key == "resolution" {
                                fields[key] = ["name": value]
                            } else {
                                fields[key] = value
                            }
                        }
                        requestBody["fields"] = fields
                    }

                    transitionRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    let (_, response) = try await URLSession.shared.data(for: transitionRequest)

                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                        Logger.shared.info("Successfully transitioned \(issueKey) to \(newStatus)")
                        await fetchMyIssues()
                        return true
                    }
                }
            }

            Logger.shared.warning("Could not find transition to status: \(newStatus)")
            return false
        } catch {
            Logger.shared.error("Failed to update issue status: \(error)")
            return false
        }
    }

    func logWork(issueKey: String, timeSpentSeconds: Int) async -> Bool {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/worklog"

        guard let url = URL(string: urlString) else {
            print("Invalid URL for logging work")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "POST"

        let requestBody: [String: Any] = [
            "timeSpentSeconds": timeSpentSeconds
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            Logger.shared.info("Logging work for \(issueKey): \(timeSpentSeconds) seconds")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Log work response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                Logger.shared.info("Successfully logged work for \(issueKey)")
                // Refresh issues to update the time logged
                await fetchMyIssues()
                return true
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error logging work: \(errorMessage)")
                }
                return false
            }
        } catch {
            Logger.shared.error("Failed to log work: \(error)")
            return false
        }
    }
}
