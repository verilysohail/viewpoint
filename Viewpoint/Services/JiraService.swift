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
    private var currentPageToken: String? = nil

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
    @Published var availableComponents: Set<String> = []

    // Epic summaries (epic key -> summary)
    @Published var epicSummaries: [String: String] = [:]

    // Current filters
    @Published var filters = IssueFilters()

    // Current JQL query
    @Published var currentJQL: String?

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
            // Only fetch metadata on initial load - no issues yet
            // Issues will be fetched when user selects a project or executes JQL
            Logger.shared.info("Loading initial data (projects and sprints only, no issues)")

            async let projectsFetch = fetchAvailableProjects()
            async let sprintsFetch = fetchSprints()

            // Wait for filter options to load
            await projectsFetch
            await sprintsFetch

            Logger.shared.info("Initial data loaded successfully")
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
            currentPageToken = nil
            issues = []
        }

        await loadMoreIssues(updateAvailableOptions: updateAvailableOptions, initialFetchLimit: initialLoadCount)
    }

    func loadMoreIssues(updateAvailableOptions: Bool = false, initialFetchLimit: Int = 500) async {
        await MainActor.run { isLoading = true }

        let jql = filters.buildJQL(userEmail: config.jiraEmail)

        let maxResults = 100
        let isInitialFetch = await MainActor.run { currentPageToken == nil && issues.isEmpty }
        var allIssues: [JiraIssue] = await MainActor.run { issues }
        var pageToken = await MainActor.run { currentPageToken }
        let fetchLimit = isInitialFetch ? initialFetchLimit : 500 // Initial fetch or subsequent "Load more"

        do {
            Logger.shared.info("JQL: \(jql)")
            Logger.shared.info("Fetching up to \(fetchLimit) more issues, pageToken: \(pageToken ?? "none")")

            var fetchedInThisBatch = 0
            var nextToken: String? = pageToken

            repeat {
                // Build URL with query parameters for /search/jql endpoint
                var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
                var queryItems = [
                    URLQueryItem(name: "jql", value: jql),
                    URLQueryItem(name: "maxResults", value: String(maxResults)),
                    URLQueryItem(name: "fields", value: "summary,status,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
                ]

                // Add nextPageToken if we have one (not on first page)
                if let token = nextToken {
                    queryItems.append(URLQueryItem(name: "nextPageToken", value: token))
                }

                components.queryItems = queryItems

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

                Logger.shared.info("Response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode != 200 {
                    // Try to parse error message from response
                    if let errorMessage = String(data: data, encoding: .utf8) {
                        Logger.shared.error("Error response (\(httpResponse.statusCode)): \(errorMessage)")
                    }
                    throw NSError(domain: "JiraAPI", code: httpResponse.statusCode,
                                 userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }

                let searchResponse = try JSONDecoder().decode(JiraSearchResponse.self, from: data)

                // Append issues from this page
                allIssues.append(contentsOf: searchResponse.issues)
                fetchedInThisBatch += searchResponse.issues.count

                // Get next page token from response
                nextToken = searchResponse.nextPageToken

                Logger.shared.info("Fetched \(searchResponse.issues.count) issues (loaded so far: \(allIssues.count), hasMore: \(nextToken != nil))")

            } while fetchedInThisBatch < fetchLimit && nextToken != nil

            Logger.shared.info("Successfully fetched \(allIssues.count) total issues")

            await MainActor.run {
                self.issues = allIssues
                self.totalIssuesAvailable = allIssues.count // Can't know total with token-based pagination
                self.hasMoreIssues = nextToken != nil
                self.currentPageToken = nextToken
                if updateAvailableOptions {
                    self.updateAvailableFilters()
                }
                self.isLoading = false
                self.errorMessage = nil
            }

            // Fetch epic summaries for all epics in the result set (only on initial fetch)
            if isInitialFetch {
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

    func searchWithJQL(_ jql: String) async {
        // Update current JQL
        await MainActor.run {
            self.currentJQL = jql
        }

        // Parse JQL and update filter selections to match the query
        await MainActor.run {
            self.parseAndApplyJQLToFilters(jql)
        }

        // Reset pagination state when executing new search
        await MainActor.run {
            isLoading = true
            currentPageToken = nil
            issues = []
        }

        let maxResults = initialLoadCount
        var allIssues: [JiraIssue] = []

        do {
            Logger.shared.info("Executing JQL search: \(jql)")

            // Build URL with query parameters (no nextPageToken for first page)
            var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
            components.queryItems = [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "fields", value: "summary,status,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
            ]

            guard let url = components.url else {
                await MainActor.run {
                    errorMessage = "Invalid URL"
                    isLoading = false
                }
                return
            }

            Logger.shared.info("Fetching from: \(url)")

            let request = createRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("JQL search response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }

            let searchResponse = try JSONDecoder().decode(JiraSearchResponse.self, from: data)
            allIssues = searchResponse.issues

            Logger.shared.info("JQL search returned \(allIssues.count) issues")

            await MainActor.run {
                self.issues = allIssues
                self.totalIssuesAvailable = allIssues.count
                self.hasMoreIssues = searchResponse.nextPageToken != nil
                self.currentPageToken = searchResponse.nextPageToken
                self.updateAvailableFilters()
                self.isLoading = false
                self.errorMessage = nil
            }

            // Fetch epic summaries
            await fetchEpicSummaries()

        } catch {
            Logger.shared.error("Error executing JQL search: \(error)")
            await MainActor.run {
                self.errorMessage = "JQL search failed: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - JQL Parsing

    private func parseAndApplyJQLToFilters(_ jql: String) {
        Logger.shared.info("Parsing JQL to update filter selections: \(jql)")

        // Reset filters before parsing
        filters.projects = []
        filters.statuses = []
        filters.assignees = []
        filters.issueTypes = []
        filters.epics = []
        filters.sprints = []
        filters.showOnlyMyIssues = false

        let lowercaseJQL = jql.lowercased()

        // Parse project filter: project IN ("Project1", "Project2") or project = "Project1"
        if let projects = parseJQLList(jql: jql, field: "project") {
            filters.projects = Set(projects)
            Logger.shared.info("Parsed projects: \(projects)")
        }

        // Parse status filter: status IN ("Done", "In Progress")
        if let statuses = parseJQLList(jql: jql, field: "status") {
            filters.statuses = Set(statuses)
            Logger.shared.info("Parsed statuses: \(statuses)")
        }

        // Parse assignee filter: assignee IN ("User1", "User2") or assignee = currentUser()
        if lowercaseJQL.contains("assignee = currentuser()") {
            filters.showOnlyMyIssues = true
            Logger.shared.info("Parsed assignee: currentUser() - setting showOnlyMyIssues = true")
        } else if let assignees = parseJQLList(jql: jql, field: "assignee") {
            filters.assignees = Set(assignees)
            filters.showOnlyMyIssues = false
            Logger.shared.info("Parsed assignees: \(assignees)")
        }

        // Parse issue type filter: type IN ("Bug", "Story") or issuetype IN (...)
        if let types = parseJQLList(jql: jql, field: "type") {
            filters.issueTypes = Set(types)
            Logger.shared.info("Parsed issue types: \(types)")
        } else if let types = parseJQLList(jql: jql, field: "issuetype") {
            filters.issueTypes = Set(types)
            Logger.shared.info("Parsed issue types (from issuetype): \(types)")
        }

        // Parse epic filter: "Epic Link" IN ("EPIC-123") or customfield_10014 IN (...)
        if let epics = parseJQLList(jql: jql, field: "epic link") {
            filters.epics = Set(epics)
            Logger.shared.info("Parsed epics: \(epics)")
        } else if let epics = parseJQLList(jql: jql, field: "customfield_10014") {
            filters.epics = Set(epics)
            Logger.shared.info("Parsed epics (from customfield): \(epics)")
        }

        // Parse sprint filter: sprint IN (123, 456)
        if let sprintStrings = parseJQLList(jql: jql, field: "sprint") {
            let sprintIds = sprintStrings.compactMap { Int($0) }
            filters.sprints = Set(sprintIds)
            Logger.shared.info("Parsed sprints: \(sprintIds)")
        }

        // Save the updated filters
        saveFilters()
    }

    private func parseJQLList(jql: String, field: String) -> [String]? {
        let lowercaseJQL = jql.lowercased()
        let lowercaseField = field.lowercased()

        // Pattern 1: field IN ("value1", "value2", "value3")
        // Pattern 2: field IN (value1, value2, value3) - for numbers/unquoted values
        // Pattern 3: field = "value"
        // Pattern 4: "field with spaces" IN (...)

        // Try to find the field in the JQL
        guard let fieldRange = lowercaseJQL.range(of: lowercaseField) else {
            return nil
        }

        // Get the substring starting from the field
        let startIndex = fieldRange.upperBound
        let substring = String(jql[startIndex...])

        // Check if it's an IN clause
        if let inRange = substring.range(of: "IN", options: [.caseInsensitive]) {
            let afterIn = String(substring[inRange.upperBound...])

            // Find the opening parenthesis
            guard let openParen = afterIn.firstIndex(of: "(") else {
                return nil
            }

            // Find the matching closing parenthesis
            guard let closeParen = afterIn.firstIndex(of: ")") else {
                return nil
            }

            // Extract the content between parentheses
            let startIdx = afterIn.index(after: openParen)
            let content = String(afterIn[startIdx..<closeParen])

            // Split by commas and clean up quotes and whitespace
            let values = content.components(separatedBy: ",").map { value in
                value.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    .trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }

            return values.isEmpty ? nil : values

        } else if let eqRange = substring.range(of: "=", options: [.caseInsensitive]) {
            // Handle field = "value"
            let afterEq = String(substring[eqRange.upperBound...])

            // Extract the value (handle both quoted and unquoted)
            let trimmed = afterEq.trimmingCharacters(in: .whitespaces)

            // Find the end of the value (either next AND/OR or end of string)
            var value = trimmed
            if let andRange = trimmed.range(of: " AND ", options: [.caseInsensitive]) {
                value = String(trimmed[..<andRange.lowerBound])
            } else if let orRange = trimmed.range(of: " OR ", options: [.caseInsensitive]) {
                value = String(trimmed[..<orRange.lowerBound])
            } else if let orderRange = trimmed.range(of: " ORDER BY ", options: [.caseInsensitive]) {
                value = String(trimmed[..<orderRange.lowerBound])
            }

            // Clean up quotes and whitespace
            let cleanValue = value.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespaces)

            return cleanValue.isEmpty ? nil : [cleanValue]
        }

        return nil
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
                    self.availableSprints = uniqueSprints // Also populate available sprints for filters
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

    func fetchAvailableProjects() async {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/project"

        guard let url = URL(string: urlString) else { return }

        let request = createRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Fetch projects response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error fetching projects: \(errorMessage)")
                }
                return
            }

            // Parse projects
            if let projects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let projectNames = projects.compactMap { $0["name"] as? String }

                Logger.shared.info("Found \(projectNames.count) accessible projects")

                await MainActor.run {
                    self.availableProjects = Set(projectNames)
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch projects: \(error)")
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
            URLQueryItem(name: "fields", value: "summary,status,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
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
        availableEpics = Set(issues.compactMap { $0.epic })

        // Merge projects from issues with independently fetched projects
        let projectsFromIssues = Set(issues.map { $0.project })
        availableProjects = availableProjects.union(projectsFromIssues)

        // Extract unique components from issues
        var componentSet: Set<String> = []
        for issue in issues {
            if let components = issue.fields.components {
                for component in components {
                    componentSet.insert(component.name)
                }
            }
        }
        availableComponents = componentSet

        // Merge sprints from issues with independently fetched sprints
        var sprintMap: [Int: JiraSprint] = Dictionary(uniqueKeysWithValues: availableSprints.map { ($0.id, $0) })
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

                // Log available transitions for debugging
                Logger.shared.info("Available transitions for \(issueKey):")
                for trans in transitions {
                    if let transName = trans["name"] as? String,
                       let to = trans["to"] as? [String: Any],
                       let toStatus = to["name"] as? String {
                        Logger.shared.info("  - Transition '\(transName)' -> Status '\(toStatus)'")
                    }
                }

                // Find the best matching transition using smart matching
                if let (matchedTransition, matchType) = findBestTransition(query: newStatus, transitions: transitions),
                   let transitionId = matchedTransition["id"] as? String,
                   let transitionName = matchedTransition["name"] as? String {

                    Logger.shared.info("Matched '\(newStatus)' to transition '\(transitionName)' using \(matchType)")

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
                        return true
                    }
                }
            }

            Logger.shared.warning("Could not find transition matching: \(newStatus)")
            return false
        } catch {
            Logger.shared.error("Failed to update issue status: \(error)")
            return false
        }
    }

    // MARK: - Smart Transition Matching

    private func findBestTransition(query: String, transitions: [[String: Any]]) -> (transition: [String: Any], matchType: String)? {
        let lowercaseQuery = query.lowercased()

        // Build list of transitions with their names and target statuses
        var transitionData: [(transition: [String: Any], name: String, targetStatus: String)] = []
        for trans in transitions {
            if let transName = trans["name"] as? String,
               let to = trans["to"] as? [String: Any],
               let toStatus = to["name"] as? String {
                transitionData.append((trans, transName, toStatus))
            }
        }

        // 1. Try exact match on target status
        if let match = transitionData.first(where: { $0.targetStatus.lowercased() == lowercaseQuery }) {
            return (match.transition, "exact status match")
        }

        // 2. Try exact match on transition name
        if let match = transitionData.first(where: { $0.name.lowercased() == lowercaseQuery }) {
            return (match.transition, "exact transition name match")
        }

        // 3. Try semantic/synonym matching
        if let match = findSemanticTransitionMatch(query: lowercaseQuery, transitions: transitionData) {
            return (match.transition, "semantic match")
        }

        // 4. Try contains match on target status
        if let match = transitionData.first(where: { $0.targetStatus.lowercased().contains(lowercaseQuery) }) {
            return (match.transition, "contains status match")
        }

        // 5. Try contains match on transition name
        if let match = transitionData.first(where: { $0.name.lowercased().contains(lowercaseQuery) }) {
            return (match.transition, "contains transition name match")
        }

        // 6. Try fuzzy word-based matching
        let queryWords = lowercaseQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var bestMatch: (transition: [String: Any], name: String, targetStatus: String)?
        var bestScore = 0

        for transData in transitionData {
            let statusWords = transData.targetStatus.lowercased().components(separatedBy: .whitespaces)
            let nameWords = transData.name.lowercased().components(separatedBy: .whitespaces)

            let statusMatches = queryWords.filter { word in statusWords.contains(where: { $0.contains(word) }) }.count
            let nameMatches = queryWords.filter { word in nameWords.contains(where: { $0.contains(word) }) }.count
            let score = statusMatches * 2 + nameMatches // Prioritize status matches

            if score > bestScore {
                bestScore = score
                bestMatch = transData
            }
        }

        if bestScore > 0, let match = bestMatch {
            return (match.transition, "fuzzy match (score: \(bestScore))")
        }

        return nil
    }

    private func findSemanticTransitionMatch(query: String, transitions: [(transition: [String: Any], name: String, targetStatus: String)]) -> (transition: [String: Any], name: String, targetStatus: String)? {
        // Define semantic groups for common status changes
        let semanticGroups: [[String]] = [
            ["done", "complete", "completed", "finish", "finished", "close", "closed", "resolve", "resolved"],
            ["start", "started", "begin", "in progress", "inprogress", "working", "in-progress"],
            ["cancel", "cancelled", "canceled", "reject", "rejected", "abort", "aborted"],
            ["todo", "to do", "backlog", "open", "new"],
            ["review", "in review", "reviewing", "code review"],
            ["testing", "test", "qa", "quality assurance"],
            ["blocked", "waiting", "on hold", "paused"]
        ]

        // Check if query matches any semantic group
        for group in semanticGroups {
            if group.contains(query) {
                // Find transition where target status or name matches any word in the same group
                for transData in transitions {
                    let statusLower = transData.targetStatus.lowercased()
                    let nameLower = transData.name.lowercased()

                    for synonym in group {
                        if statusLower.contains(synonym) || nameLower.contains(synonym) {
                            return transData
                        }
                    }
                }
            }
        }

        return nil
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

    func updateIssue(issueKey: String, fields: [String: Any]) async -> Bool {
        // Check if status change is requested - this needs special handling
        if let newStatus = fields["status"] as? String {
            // Extract resolution if provided
            var fieldValues: [String: String] = [:]
            if let resolution = fields["resolution"] as? String {
                fieldValues["resolution"] = resolution
            }

            Logger.shared.info("Detected status change request for \(issueKey) to '\(newStatus)'")
            return await updateIssueStatus(issueKey: issueKey, newStatus: newStatus, fieldValues: fieldValues)
        }

        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for updating issue")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "PUT"

        // Map AI fields to Jira API format
        var jiraFields: [String: Any] = [:]

        // Handle different field types
        for (key, value) in fields {
            switch key.lowercased() {
            case "status":
                // Already handled above
                Logger.shared.warning("Status field should have been handled by transition API")
                continue

            case "resolution":
                // Resolution is only set during transitions, not via update
                Logger.shared.warning("Resolution can only be set during status transitions")
                continue

            case "summary":
                jiraFields["summary"] = value

            case "description":
                jiraFields["description"] = value

            case "assignee":
                if let assigneeEmail = value as? String {
                    jiraFields["assignee"] = ["emailAddress": assigneeEmail]
                }

            case "priority":
                if let priority = value as? String {
                    jiraFields["priority"] = ["name": priority]
                }

            case "labels":
                if let labels = value as? [String] {
                    jiraFields["labels"] = labels
                } else if let labelString = value as? String {
                    jiraFields["labels"] = labelString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }

            case "components":
                if let components = value as? [String] {
                    // Smart lookup for each component
                    var resolvedComponents: [[String: String]] = []
                    for componentQuery in components {
                        if let matchedComponent = await findComponentByName(componentQuery) {
                            resolvedComponents.append(["name": matchedComponent])
                            Logger.shared.info("Matched component '\(componentQuery)' to: \(matchedComponent)")
                        } else {
                            resolvedComponents.append(["name": componentQuery])
                            Logger.shared.warning("Could not find component matching '\(componentQuery)', using as-is")
                        }
                    }
                    jiraFields["components"] = resolvedComponents
                } else if let componentString = value as? String {
                    let componentQueries = componentString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    var resolvedComponents: [[String: String]] = []
                    for componentQuery in componentQueries {
                        if let matchedComponent = await findComponentByName(componentQuery) {
                            resolvedComponents.append(["name": matchedComponent])
                            Logger.shared.info("Matched component '\(componentQuery)' to: \(matchedComponent)")
                        } else {
                            resolvedComponents.append(["name": componentQuery])
                            Logger.shared.warning("Could not find component matching '\(componentQuery)', using as-is")
                        }
                    }
                    jiraFields["components"] = resolvedComponents
                }

            case "originalestimate", "timetracking.originalestimate":
                if let estimate = value as? String {
                    jiraFields["timetracking"] = ["originalEstimate": estimate]
                }

            case "remainingestimate", "timetracking.remainingestimate":
                if let estimate = value as? String {
                    var timetracking = jiraFields["timetracking"] as? [String: String] ?? [:]
                    timetracking["remainingEstimate"] = estimate
                    jiraFields["timetracking"] = timetracking
                }

            case "sprint":
                if let sprintValue = value as? String {
                    if sprintValue.lowercased() == "current" {
                        let activeSprints = await MainActor.run {
                            self.availableSprints.filter { $0.state.lowercased() == "active" }
                        }
                        if let currentSprint = activeSprints.first {
                            jiraFields["customfield_10020"] = currentSprint.id
                        }
                    } else {
                        // Try to find sprint by name
                        let matchingSprint = await findSprintByName(sprintValue)
                        if let sprint = matchingSprint {
                            jiraFields["customfield_10020"] = sprint.id
                            Logger.shared.info("Matched sprint '\(sprintValue)' to: \(sprint.name) (ID: \(sprint.id))")
                        } else {
                            Logger.shared.warning("Could not find sprint matching: \(sprintValue)")
                        }
                    }
                }

            case "epic":
                if let epicQuery = value as? String {
                    // Try to find epic by semantic search
                    let matchingEpic = await findEpicByName(epicQuery)
                    if let epicKey = matchingEpic {
                        jiraFields["customfield_10014"] = epicKey
                        Logger.shared.info("Matched epic '\(epicQuery)' to: \(epicKey)")
                    } else {
                        // Fallback to using it as-is (might be exact epic key)
                        jiraFields["customfield_10014"] = epicQuery
                        Logger.shared.warning("Could not find epic matching '\(epicQuery)', using as-is")
                    }
                }

            default:
                Logger.shared.warning("Unknown field: \(key)")
            }
        }

        let requestBody: [String: Any] = ["fields": jiraFields]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            Logger.shared.info("Updating issue \(issueKey) with fields: \(jiraFields)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Update issue response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                Logger.shared.info("Successfully updated issue: \(issueKey)")
                return true
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error updating issue: \(errorMessage)")
                }
                return false
            }
        } catch {
            Logger.shared.error("Failed to update issue: \(error)")
            return false
        }
    }

    func addComment(issueKey: String, comment: String) async -> Bool {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/comment"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for adding comment")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "POST"

        let requestBody: [String: Any] = [
            "body": [
                "type": "doc",
                "version": 1,
                "content": [
                    [
                        "type": "paragraph",
                        "content": [
                            [
                                "type": "text",
                                "text": comment
                            ]
                        ]
                    ]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            Logger.shared.info("Adding comment to \(issueKey)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Add comment response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                Logger.shared.info("Successfully added comment to \(issueKey)")
                return true
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error adding comment: \(errorMessage)")
                }
                return false
            }
        } catch {
            Logger.shared.error("Failed to add comment: \(error)")
            return false
        }
    }

    func deleteIssue(issueKey: String) async -> Bool {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for deleting issue")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "DELETE"

        do {
            Logger.shared.info("Deleting issue \(issueKey)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Delete issue response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                Logger.shared.info("Successfully deleted issue \(issueKey)")
                return true
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error deleting issue: \(errorMessage)")
                }
                return false
            }
        } catch {
            Logger.shared.error("Failed to delete issue: \(error)")
            return false
        }
    }

    func assignIssue(issueKey: String, assigneeEmail: String) async -> Bool {
        return await updateIssue(issueKey: issueKey, fields: ["assignee": assigneeEmail])
    }

    func addWatcher(issueKey: String, watcherEmail: String) async -> Bool {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/watchers"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for adding watcher")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "\"\(watcherEmail)\"".data(using: .utf8)

        do {
            Logger.shared.info("Adding watcher to \(issueKey): \(watcherEmail)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Add watcher response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                Logger.shared.info("Successfully added watcher to \(issueKey)")
                return true
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error adding watcher: \(errorMessage)")
                }
                return false
            }
        } catch {
            Logger.shared.error("Failed to add watcher: \(error)")
            return false
        }
    }

    func linkIssues(issueKey: String, linkedIssueKey: String, linkType: String) async -> Bool {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issueLink"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for linking issues")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "POST"

        let requestBody: [String: Any] = [
            "type": ["name": linkType],
            "inwardIssue": ["key": issueKey],
            "outwardIssue": ["key": linkedIssueKey]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            Logger.shared.info("Linking \(issueKey) to \(linkedIssueKey) with type \(linkType)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Link issues response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                Logger.shared.info("Successfully linked issues")
                return true
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error linking issues: \(errorMessage)")
                }
                return false
            }
        } catch {
            Logger.shared.error("Failed to link issues: \(error)")
            return false
        }
    }

    func createIssue(fields: [String: Any]) async -> (success: Bool, issueKey: String?) {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for creating issue")
            return (false, nil)
        }

        var request = createRequest(url: url)
        request.httpMethod = "POST"

        // Map AI fields to Jira API format
        var jiraFields: [String: Any] = [:]

        // Required: Project
        if let projectKey = fields["project"] as? String {
            jiraFields["project"] = ["key": projectKey]
        } else {
            Logger.shared.error("Missing required field: project")
            return (false, nil)
        }

        // Required: Summary
        if let summary = fields["summary"] as? String {
            jiraFields["summary"] = summary
        } else {
            Logger.shared.error("Missing required field: summary")
            return (false, nil)
        }

        // Required: Issue Type
        if let issueType = fields["type"] as? String {
            jiraFields["issuetype"] = ["name": issueType]
        } else {
            // Default to Story if not specified
            jiraFields["issuetype"] = ["name": "Story"]
        }

        // Optional: Assignee (use email or accountId)
        if let assignee = fields["assignee"] as? String {
            // Try to use email first, fallback to accountId
            jiraFields["assignee"] = ["emailAddress": assignee]
        }

        // Optional: Original Estimate
        if let estimateStr = fields["originalEstimate"] as? String {
            // Convert "1.5h" or "1h 30m" to Jira format
            jiraFields["timetracking"] = ["originalEstimate": estimateStr]
        }

        // Optional: Sprint (needs sprint ID)
        if let sprintValue = fields["sprint"] as? String {
            if sprintValue.lowercased() == "current" {
                // Find the currently active sprint
                let activeSprints = await MainActor.run {
                    self.availableSprints.filter { $0.state.lowercased() == "active" }
                }
                if let currentSprint = activeSprints.first {
                    jiraFields["customfield_10020"] = currentSprint.id
                    Logger.shared.info("Using current sprint: \(currentSprint.name) (ID: \(currentSprint.id))")
                }
            } else {
                // Try to find sprint by name
                let matchingSprint = await findSprintByName(sprintValue)
                if let sprint = matchingSprint {
                    jiraFields["customfield_10020"] = sprint.id
                    Logger.shared.info("Matched sprint '\(sprintValue)' to: \(sprint.name) (ID: \(sprint.id))")
                } else {
                    Logger.shared.warning("Could not find sprint matching: \(sprintValue)")
                }
            }
        }

        // Optional: Epic (needs epic key)
        if let epicQuery = fields["epic"] as? String {
            // Try to find epic by semantic search
            let matchingEpic = await findEpicByName(epicQuery)
            if let epicKey = matchingEpic {
                jiraFields["customfield_10014"] = epicKey
                Logger.shared.info("Matched epic '\(epicQuery)' to: \(epicKey)")
            } else {
                // Fallback to using it as-is (might be exact epic key)
                jiraFields["customfield_10014"] = epicQuery
                Logger.shared.warning("Could not find epic matching '\(epicQuery)', using as-is")
            }
        }

        // Optional: Components
        if let components = fields["components"] as? [String] {
            // Smart lookup for each component
            var resolvedComponents: [[String: String]] = []
            for componentQuery in components {
                if let matchedComponent = await findComponentByName(componentQuery) {
                    resolvedComponents.append(["name": matchedComponent])
                } else {
                    // Use as-is if no match found
                    resolvedComponents.append(["name": componentQuery])
                    Logger.shared.warning("Could not find component matching '\(componentQuery)', using as-is")
                }
            }
            jiraFields["components"] = resolvedComponents
        } else if let componentString = fields["components"] as? String {
            let componentQueries = componentString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var resolvedComponents: [[String: String]] = []
            for componentQuery in componentQueries {
                if let matchedComponent = await findComponentByName(componentQuery) {
                    resolvedComponents.append(["name": matchedComponent])
                } else {
                    resolvedComponents.append(["name": componentQuery])
                    Logger.shared.warning("Could not find component matching '\(componentQuery)', using as-is")
                }
            }
            jiraFields["components"] = resolvedComponents
        } else {
            // Default: try to find "Management Tasks" component
            if let managementTasksComponent = await findComponentByName("Management Tasks") {
                jiraFields["components"] = [["name": managementTasksComponent]]
                Logger.shared.info("Using default component: \(managementTasksComponent)")
            } else {
                // Fallback to literal "Management Tasks" if not found in available components
                jiraFields["components"] = [["name": "Management Tasks"]]
                Logger.shared.warning("Management Tasks component not found in loaded issues, using literal value")
            }
        }

        let requestBody: [String: Any] = ["fields": jiraFields]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            Logger.shared.info("Creating issue with fields: \(jiraFields)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Create issue response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 201 {
                // Parse response to get the new issue key
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let issueKey = json["key"] as? String {
                    Logger.shared.info("Successfully created issue: \(issueKey)")
                    return (true, issueKey)
                }
                return (true, nil)
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error creating issue: \(errorMessage)")
                }
                return (false, nil)
            }
        } catch {
            Logger.shared.error("Failed to create issue: \(error)")
            return (false, nil)
        }
    }

    // MARK: - Semantic Search Helpers

    func findSprintByName(_ query: String) async -> JiraSprint? {
        let sprints = await MainActor.run { self.availableSprints }
        let lowercaseQuery = query.lowercased()

        // First try exact match
        if let exactMatch = sprints.first(where: { $0.name.lowercased() == lowercaseQuery }) {
            return exactMatch
        }

        // Then try contains match
        if let containsMatch = sprints.first(where: { $0.name.lowercased().contains(lowercaseQuery) }) {
            return containsMatch
        }

        // Finally try fuzzy match - find sprint name that contains most query words
        let queryWords = lowercaseQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var bestMatch: JiraSprint?
        var bestScore = 0

        for sprint in sprints {
            let sprintName = sprint.name.lowercased()
            let matchingWords = queryWords.filter { sprintName.contains($0) }
            let score = matchingWords.count

            if score > bestScore {
                bestScore = score
                bestMatch = sprint
            }
        }

        // Only return if at least one word matched
        return bestScore > 0 ? bestMatch : nil
    }

    func findEpicByName(_ query: String) async -> String? {
        // First, search in currently loaded epics
        let summaries = await MainActor.run { self.epicSummaries }
        let lowercaseQuery = query.lowercased()

        Logger.shared.info("Searching for epic matching query: '\(query)'")
        Logger.shared.info("Available epics in loaded issues: \(summaries.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")

        // First try exact match on epic key (e.g., "SETI-123")
        if let exactKey = summaries.keys.first(where: { $0.lowercased() == lowercaseQuery }) {
            Logger.shared.info("Found exact key match in loaded epics: \(exactKey)")
            return exactKey
        }

        // Then try exact match on summary
        if let exactSummary = summaries.first(where: { $0.value.lowercased() == lowercaseQuery }) {
            Logger.shared.info("Found exact summary match in loaded epics: \(exactSummary.key)")
            return exactSummary.key
        }

        // Try contains match on summary
        if let containsMatch = summaries.first(where: { $0.value.lowercased().contains(lowercaseQuery) }) {
            Logger.shared.info("Found contains match in loaded epics: \(containsMatch.key) (\(containsMatch.value))")
            return containsMatch.key
        }

        // Try fuzzy match on loaded epics
        let queryWords = lowercaseQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var bestMatch: String?
        var bestScore = 0

        for (key, summary) in summaries {
            let summaryLower = summary.lowercased()
            let matchingWords = queryWords.filter { summaryLower.contains($0) }
            let score = matchingWords.count

            if score > bestScore {
                bestScore = score
                bestMatch = key
            }
        }

        if bestScore > 0 && bestMatch != nil {
            Logger.shared.info("Found fuzzy match in loaded epics: \(bestMatch!) (score: \(bestScore))")
            return bestMatch
        }

        // Not found in loaded epics - search ALL epics in the project
        Logger.shared.info("Epic not found in loaded issues, searching all epics in project...")
        return await searchAllEpicsInProject(query: query, queryWords: queryWords)
    }

    private func searchAllEpicsInProject(query: String, queryWords: [String]) async -> String? {
        // Get the current project(s)
        let projects = await MainActor.run { Array(self.filters.projects) }
        guard !projects.isEmpty else {
            Logger.shared.warning("No project selected, cannot search all epics")
            return nil
        }

        // Build JQL to find all epics in the project
        let projectList = projects.map { "\"\($0)\"" }.joined(separator: ", ")
        let jql = "project IN (\(projectList)) AND type = Epic ORDER BY created DESC"

        var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "summary")
        ]

        guard let url = components.url else {
            Logger.shared.error("Invalid URL for epic search")
            return nil
        }

        let request = createRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.shared.error("Failed to fetch all epics")
                return nil
            }

            let searchResponse = try JSONDecoder().decode(EpicSummaryResponse.self, from: data)
            let allEpics = Dictionary(uniqueKeysWithValues: searchResponse.issues.map { ($0.key, $0.fields.summary) })

            Logger.shared.info("Found \(allEpics.count) total epics in project")

            let lowercaseQuery = query.lowercased()

            // Try exact match on key
            if let exactKey = allEpics.keys.first(where: { $0.lowercased() == lowercaseQuery }) {
                Logger.shared.info("Found exact key match in all epics: \(exactKey)")
                return exactKey
            }

            // Try exact match on summary
            if let exactSummary = allEpics.first(where: { $0.value.lowercased() == lowercaseQuery }) {
                Logger.shared.info("Found exact summary match in all epics: \(exactSummary.key)")
                return exactSummary.key
            }

            // Try contains match
            if let containsMatch = allEpics.first(where: { $0.value.lowercased().contains(lowercaseQuery) }) {
                Logger.shared.info("Found contains match in all epics: \(containsMatch.key) (\(containsMatch.value))")
                return containsMatch.key
            }

            // Try fuzzy match
            var bestMatch: String?
            var bestScore = 0

            for (key, summary) in allEpics {
                let summaryLower = summary.lowercased()
                let matchingWords = queryWords.filter { summaryLower.contains($0) }
                let score = matchingWords.count

                if score > bestScore {
                    bestScore = score
                    bestMatch = key
                }
            }

            if bestScore > 0 && bestMatch != nil {
                Logger.shared.info("Found fuzzy match in all epics: \(bestMatch!) (score: \(bestScore))")
                return bestMatch
            }

            Logger.shared.warning("No epic match found for query: '\(query)' even after searching all epics")
            return nil

        } catch {
            Logger.shared.error("Error searching all epics: \(error)")
            return nil
        }
    }

    func findComponentByName(_ query: String) async -> String? {
        let components = await MainActor.run { self.availableComponents }
        let lowercaseQuery = query.lowercased()

        Logger.shared.info("Searching for component matching query: '\(query)'")
        Logger.shared.info("Available components: \(components.sorted().joined(separator: ", "))")

        // First try exact match
        if let exactMatch = components.first(where: { $0.lowercased() == lowercaseQuery }) {
            Logger.shared.info("Found exact component match: \(exactMatch)")
            return exactMatch
        }

        // Then try contains match
        if let containsMatch = components.first(where: { $0.lowercased().contains(lowercaseQuery) }) {
            Logger.shared.info("Found contains match: \(containsMatch)")
            return containsMatch
        }

        // Finally try fuzzy match - find component name that contains most query words
        let queryWords = lowercaseQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var bestMatch: String?
        var bestScore = 0

        for component in components {
            let componentLower = component.lowercased()
            let matchingWords = queryWords.filter { componentLower.contains($0) }
            let score = matchingWords.count

            if score > bestScore {
                bestScore = score
                bestMatch = component
            }
        }

        // Only return if at least one word matched
        if bestScore > 0 && bestMatch != nil {
            Logger.shared.info("Found fuzzy component match: \(bestMatch!) (score: \(bestScore))")
            return bestMatch
        }

        Logger.shared.warning("No component match found for query: '\(query)'")
        return nil
    }
}
