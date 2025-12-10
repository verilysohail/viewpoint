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

    let config = Configuration.shared
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
    @Published var availableResolutions: Set<String> = ["Done", "Won't Do", "Duplicate", "Cannot Reproduce", "Cancelled"]

    // Epic summaries (epic key -> summary)
    @Published var epicSummaries: [String: String] = [:]

    // Project name to key mapping (project name -> project key)
    @Published var projectNameToKey: [String: String] = [:]

    // Sprint to project associations (sprint ID -> set of project keys)
    var sprintProjectMap: [Int: Set<String>] = [:]

    // Cache of sprints per project key
    @Published var projectSprintsCache: [String: [JiraSprint]] = [:]

    // Current filters
    @Published var filters = IssueFilters()

    // Selected issues (shared across windows for multi-select)
    @Published var selectedIssues: Set<JiraIssue.ID> = []

    // Current JQL query
    @Published var currentJQL: String?

    // Current user's Jira account ID (cached)
    private var currentUserAccountId: String? {
        get { UserDefaults.standard.string(forKey: "jiraAccountId") }
        set { UserDefaults.standard.set(newValue, forKey: "jiraAccountId") }
    }

    // Filtered sprints based on selected projects
    var filteredSprints: [JiraSprint] {
        // If no projects selected, show sprints from current issues
        if filters.projects.isEmpty {
            // Extract sprints from currently loaded issues
            let sprintsInIssues = Set(issues.compactMap { issue in
                issue.fields.customfield_10020?.compactMap { $0.id }
            }.flatMap { $0 })

            return availableSprints.filter { sprintsInIssues.contains($0.id) }
        } else {
            // Map selected project names to project keys
            let projectKeys = Set(issues
                .filter { filters.projects.contains($0.project) }
                .map { $0.fields.project.key })

            Logger.shared.info("Filtering sprints for projects: \(filters.projects)")
            Logger.shared.info("Project keys: \(projectKeys)")

            // Use cached sprints for these projects if available
            let cachedProjectSprints = projectKeys.flatMap { projectKey in
                projectSprintsCache[projectKey] ?? []
            }

            if !cachedProjectSprints.isEmpty {
                Logger.shared.info("Returning \(cachedProjectSprints.count) cached sprints for projects")
                return cachedProjectSprints.sorted { $0.id > $1.id }
            }

            // Otherwise, trigger async fetch and return sprints from issues for now
            Logger.shared.info("No cached sprints, fetching from API and showing issue sprints for now")
            for projectKey in projectKeys {
                Task {
                    await fetchAndCacheSprintsForProject(projectKey: projectKey)
                }
            }

            // Return sprints from currently loaded issues as a fallback
            let sprintsInProjects = Set(issues
                .filter { filters.projects.contains($0.project) }
                .compactMap { $0.fields.customfield_10020?.compactMap { $0.id } }
                .flatMap { $0 })

            return availableSprints.filter { sprintsInProjects.contains($0.id) }
        }
    }

    init() {
        // Don't auto-load persisted filters on startup - users should use saved views instead
        // Initialize previous projects to empty to avoid false change detection
        previousProjects = filters.projects
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
        // Initialize previous projects to current state to avoid false change detection
        previousProjects = filters.projects
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
            Logger.shared.info("Loading initial data (projects, sprints, and current user)")

            // Run all fetches concurrently
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchAvailableProjects() }
                group.addTask { await self.fetchSprints() }
                group.addTask { await self.fetchCurrentUser() }
            }

            Logger.shared.info("Initial data loaded successfully")
        }
    }

    func refresh() {
        Task {
            await fetchMyIssues(updateAvailableOptions: true)
        }
    }

    // MARK: - API Requests

    func createRequest(url: URL) -> URLRequest {
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

        // Use currentJQL if available (from direct JQL search), otherwise build from filters
        let jql = await MainActor.run {
            if let current = currentJQL, !current.isEmpty {
                return current
            }
            return filters.buildJQL(userEmail: config.jiraEmail)
        }

        let maxResults = 100
        let isInitialFetch = await MainActor.run { currentPageToken == nil && issues.isEmpty }
        var allIssues: [JiraIssue] = await MainActor.run { issues }
        let pageToken = await MainActor.run { currentPageToken }
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
                    URLQueryItem(name: "fields", value: "summary,status,resolution,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
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

            // Capture values before MainActor to avoid Swift 6 concurrency issues
            let finalIssues = allIssues
            let finalNextToken = nextToken

            await MainActor.run {
                self.issues = finalIssues
                self.totalIssuesAvailable = finalIssues.count // Can't know total with token-based pagination
                self.hasMoreIssues = finalNextToken != nil
                self.currentPageToken = finalNextToken
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
                URLQueryItem(name: "fields", value: "summary,status,resolution,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
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

            // Capture values before MainActor to avoid Swift 6 concurrency issues
            let finalIssues = allIssues
            let finalNextToken = searchResponse.nextPageToken

            await MainActor.run {
                self.issues = finalIssues
                self.totalIssuesAvailable = finalIssues.count
                self.hasMoreIssues = finalNextToken != nil
                self.currentPageToken = finalNextToken
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
        // Note: We skip parsing status if it uses != or NOT IN operators since filters don't support negation
        if !lowercaseJQL.contains("status !=") && !lowercaseJQL.contains("status not in") {
            if let statuses = parseJQLList(jql: jql, field: "status") {
                filters.statuses = Set(statuses)
                Logger.shared.info("Parsed statuses: \(statuses)")
            }
        } else {
            Logger.shared.info("Skipping status filter parsing - JQL uses negation (!=, NOT IN) which filters don't support")
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

    func fetchAndCacheSprintsForProject(projectKey: String) async {
        Logger.shared.info("Fetching sprints for project: \(projectKey)")

        // Check if already cached
        let cached = await MainActor.run { projectSprintsCache[projectKey] }
        if cached != nil {
            Logger.shared.info("Sprints for \(projectKey) already cached")
            return
        }

        // Fetch boards for this project
        let urlString = "\(config.jiraBaseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)&type=scrum"
        guard let url = URL(string: urlString) else { return }

        let request = createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let boards = json["values"] as? [[String: Any]] {

                Logger.shared.info("Found \(boards.count) Scrum boards for project \(projectKey)")

                var allSprints: [JiraSprint] = []

                for board in boards {
                    if let boardId = board["id"] as? Int {
                        let boardSprints = await fetchSprintsForBoard(boardId: boardId)
                        allSprints.append(contentsOf: boardSprints)
                        Logger.shared.info("Board \(boardId) contributed \(boardSprints.count) sprints for \(projectKey)")
                    }
                }

                // Remove duplicates
                let uniqueSprints = Dictionary(grouping: allSprints, by: { $0.id })
                    .compactMap { $0.value.first }
                    .sorted { $0.id > $1.id }

                Logger.shared.info("Caching \(uniqueSprints.count) total sprints for project \(projectKey)")

                await MainActor.run {
                    self.projectSprintsCache[projectKey] = uniqueSprints
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch sprints for project \(projectKey): \(error)")
        }
    }

    func fetchSprints() async {
        // Sprints are now fetched on-demand per project when needed
        // This function is kept for compatibility but does nothing
        Logger.shared.info("fetchSprints() called - sprints will be fetched on-demand per project")
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
                var nameToKey: [String: String] = [:]

                for project in projects {
                    if let name = project["name"] as? String,
                       let key = project["key"] as? String {
                        nameToKey[name] = key
                    }
                }

                Logger.shared.info("Found \(projectNames.count) accessible projects")

                // Capture values before MainActor to avoid Swift 6 concurrency issues
                let finalNameToKey = nameToKey

                await MainActor.run {
                    self.availableProjects = Set(projectNames)
                    self.projectNameToKey = finalNameToKey
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch projects: \(error)")
        }
    }

    func fetchCurrentUser() async {
        // Skip if already cached
        if currentUserAccountId != nil {
            Logger.shared.info("Using cached account ID: \(currentUserAccountId!)")
            return
        }

        let urlString = "\(config.jiraBaseURL)/rest/api/3/myself"
        guard let url = URL(string: urlString) else { return }

        let request = createRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Fetch current user response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accountId = json["accountId"] as? String {
                currentUserAccountId = accountId
                Logger.shared.info("Cached current user account ID: \(accountId)")
            } else {
                Logger.shared.error("Failed to fetch current user account ID")
            }
        } catch {
            Logger.shared.error("Failed to fetch current user: \(error)")
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
            URLQueryItem(name: "fields", value: "summary,status,resolution,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
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
                // Merge new summaries with existing ones (don't replace)
                for (key, value) in summaries {
                    self.epicSummaries[key] = value
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch epic summaries: \(error)")
        }
    }

    private func updateAvailableFilters() {
        availableStatuses = Set(issues.map { $0.status })
        availableAssignees = Set(issues.compactMap { $0.assignee })
        availableIssueTypes = Set(issues.map { $0.issueType })

        // Merge epics from issues with previously seen epics (don't replace)
        let epicsFromIssues = Set(issues.compactMap { $0.epic })
        availableEpics = availableEpics.union(epicsFromIssues)

        // Merge projects from issues with independently fetched projects
        let projectsFromIssues = Set(issues.map { $0.project })
        availableProjects = availableProjects.union(projectsFromIssues)

        // Extract unique components from issues
        var componentSet: Set<String> = []
        for issue in issues {
            for component in issue.fields.components {
                componentSet.insert(component.name)
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

    // Track previous project selection to detect changes
    private var previousProjects: Set<String> = []

    func applyFilters(updateOptions: Bool = false, fromSavedView: Bool = false) {
        saveFilters()

        // Clear currentJQL when applying filters - we want to use the filters, not old JQL
        // This fixes the bug where saved view JQL persists after clearing filters
        if !fromSavedView {
            currentJQL = nil
        }

        // Auto-detect if projects changed - if so, update options to populate filters
        let projectsChanged = previousProjects != filters.projects
        let shouldUpdateOptions = updateOptions || projectsChanged

        if projectsChanged {
            previousProjects = filters.projects
        }

        // Clear current view tracking if this is a manual filter change (not from applying a saved view)
        if !fromSavedView {
            NotificationCenter.default.post(name: NSNotification.Name("ClearCurrentView"), object: nil)
        }

        Task {
            await fetchMyIssues(updateAvailableOptions: shouldUpdateOptions)
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
        // First, get available transitions for this issue (with field expansion to get allowed values)
        let transitionsURL = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/transitions?expand=transitions.fields"

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
                if let (matchedTransition, matchType) = findBestTransition(query: newStatus, transitions: transitions) {
                    Logger.shared.info("Matched '\(newStatus)' to transition using \(matchType)")
                    Logger.shared.info("Matched transition keys: \(matchedTransition.keys.joined(separator: ", "))")

                    // Transition ID might be String or Int
                    let transitionId: String
                    if let idString = matchedTransition["id"] as? String {
                        transitionId = idString
                    } else if let idInt = matchedTransition["id"] as? Int {
                        transitionId = String(idInt)
                    } else {
                        Logger.shared.error("Failed to extract transition ID from matched transition (not String or Int)")
                        return false
                    }
                    guard let transitionName = matchedTransition["name"] as? String else {
                        Logger.shared.error("Failed to extract transition name from matched transition")
                        return false
                    }
                    guard let to = matchedTransition["to"] as? [String: Any] else {
                        Logger.shared.error("Failed to extract 'to' status from matched transition")
                        return false
                    }
                    guard let targetStatus = to["name"] as? String else {
                        Logger.shared.error("Failed to extract target status name from 'to'")
                        return false
                    }

                    Logger.shared.info("Matched '\(newStatus)' to transition '\(transitionName)' (ID: \(transitionId)) -> Status '\(targetStatus)'")

                    // Execute the transition
                    var transitionRequest = createRequest(url: url)
                    transitionRequest.httpMethod = "POST"

                    var requestBody: [String: Any] = [
                        "transition": ["id": transitionId]
                    ]

                    // Add field values if provided (already validated by AIService)
                    if !fieldValues.isEmpty {
                        var fields: [String: Any] = [:]
                        for (key, value) in fieldValues {
                            // Wrap values in {"name": value} format for Jira API
                            fields[key] = ["name": value]
                            Logger.shared.info("Adding field '\(key)' with value '\(value)'")
                        }
                        requestBody["fields"] = fields
                    }

                    transitionRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    // Log the request body for debugging
                    if let bodyData = transitionRequest.httpBody,
                       let bodyString = String(data: bodyData, encoding: .utf8) {
                        Logger.shared.info("Transition request body: \(bodyString)")
                    }

                    let (responseData, response) = try await URLSession.shared.data(for: transitionRequest)

                    // Log response status
                    if let httpResponse = response as? HTTPURLResponse {
                        Logger.shared.info("Transition response status: \(httpResponse.statusCode)")
                        if let responseString = String(data: responseData, encoding: .utf8) {
                            Logger.shared.info("Transition response body: \(responseString)")
                        }
                    }

                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                        Logger.shared.info("Successfully transitioned \(issueKey) to \(newStatus)")

                        // Optimistically update local issues array
                        await MainActor.run {
                            if let index = issues.firstIndex(where: { $0.key == issueKey }) {
                                let newStatusField = StatusField(name: targetStatus, statusCategory: nil)
                                let updatedFields = issues[index].fields.withStatus(newStatusField)
                                issues[index] = issues[index].withFields(updatedFields)
                                Logger.shared.info("Optimistically updated \(issueKey) status to '\(targetStatus)' in local cache")
                            }
                        }

                        return true
                    }
                }

                Logger.shared.warning("Could not find transition matching: \(newStatus)")
            }

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
            ["done", "complete", "completed", "finish", "finished", "close", "closed", "resolve", "resolved", "cancel", "cancelled", "canceled"],
            ["start", "started", "begin", "in progress", "inprogress", "working", "in-progress"],
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

    func searchUsers(query: String) async -> [(displayName: String, accountId: String, email: String)] {
        // Use Jira's user search API to find users by name
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(config.jiraBaseURL)/rest/api/3/user/search?query=\(encodedQuery)&maxResults=10"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for user search")
            return []
        }

        let request = createRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 200,
               let usersArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {

                let users = usersArray.compactMap { userDict -> (String, String, String)? in
                    guard let displayName = userDict["displayName"] as? String,
                          let accountId = userDict["accountId"] as? String else {
                        return nil
                    }
                    let email = userDict["emailAddress"] as? String ?? ""
                    return (displayName, accountId, email)
                }

                return users
            }
        } catch {
            Logger.shared.error("Failed to search users: \(error)")
        }

        return []
    }

    func fetchJQLAutocompleteSuggestions(fieldName: String, query: String = "") async -> [String] {
        // Use Jira's autocomplete API to get all available values for a field
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        // Map common field names to their Jira autocomplete equivalents
        let apiFieldName: String
        switch fieldName.lowercased() {
        case "assignee":
            apiFieldName = "assignee"
        case "project":
            apiFieldName = "project"
        case "status":
            apiFieldName = "status"
        case "type", "issuetype":
            apiFieldName = "issuetype"
        case "priority":
            apiFieldName = "priority"
        case "component", "components":
            apiFieldName = "component"
        default:
            apiFieldName = fieldName
        }

        let urlString = "\(config.jiraBaseURL)/rest/api/3/jql/autocompletedata/suggestions?fieldName=\(apiFieldName)&fieldValue=\(encodedQuery)"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for JQL autocomplete")
            return []
        }

        let request = createRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {

                // Extract display names from results and strip HTML tags
                let suggestions = results.compactMap { result -> String? in
                    if let displayName = result["displayName"] as? String {
                        return stripHTMLTags(from: displayName)
                    } else if let value = result["value"] as? String {
                        return stripHTMLTags(from: value)
                    }
                    return nil
                }

                Logger.shared.info("Fetched \(suggestions.count) autocomplete suggestions for \(fieldName)")
                return suggestions
            }
        } catch {
            Logger.shared.error("Failed to fetch autocomplete suggestions: \(error)")
        }

        return []
    }

    func moveIssueToSprint(issueKey: String, sprintId: Int?) async -> Bool {
        if let sprintId = sprintId {
            // Move issue to sprint using Agile API
            let urlString = "\(config.jiraBaseURL)/rest/agile/1.0/sprint/\(sprintId)/issue"

            guard let url = URL(string: urlString) else {
                Logger.shared.error("Invalid URL for moving issue to sprint")
                return false
            }

            var request = createRequest(url: url)
            request.httpMethod = "POST"

            let requestBody: [String: Any] = [
                "issues": [issueKey]
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                Logger.shared.info("Moving \(issueKey) to sprint \(sprintId)")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                Logger.shared.info("Move to sprint response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    Logger.shared.info("Successfully moved \(issueKey) to sprint \(sprintId)")

                    // Optimistically update local issues array
                    await MainActor.run {
                        if let index = issues.firstIndex(where: { $0.key == issueKey }) {
                            // Find sprint details from availableSprints
                            if let sprint = availableSprints.first(where: { $0.id == sprintId }) {
                                let sprintField = SprintField(id: sprint.id, name: sprint.name, state: sprint.state)
                                let updatedFields = issues[index].fields.withSprint([sprintField])
                                issues[index] = issues[index].withFields(updatedFields)
                                Logger.shared.info("Optimistically updated \(issueKey) sprint in local cache")
                            }
                        }
                    }

                    return true
                } else {
                    if let errorMessage = String(data: data, encoding: .utf8) {
                        Logger.shared.error("Error moving to sprint: \(errorMessage)")
                    }
                    return false
                }
            } catch {
                Logger.shared.error("Failed to move issue to sprint: \(error)")
                return false
            }
        } else {
            // Move issue to backlog by setting customfield_10020 to null
            // Use the standard update API with the sprint custom field
            let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)"

            guard let url = URL(string: urlString) else {
                Logger.shared.error("Invalid URL for moving issue to backlog")
                return false
            }

            var request = createRequest(url: url)
            request.httpMethod = "PUT"

            let requestBody: [String: Any] = [
                "fields": [
                    "customfield_10020": NSNull()
                ]
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                Logger.shared.info("Moving \(issueKey) to backlog (removing from sprint)")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                Logger.shared.info("Move to backlog response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    Logger.shared.info("Successfully moved \(issueKey) to backlog")

                    // Optimistically update local issues array
                    await MainActor.run {
                        if let index = issues.firstIndex(where: { $0.key == issueKey }) {
                            let updatedFields = issues[index].fields.withSprint(nil)
                            issues[index] = issues[index].withFields(updatedFields)
                            Logger.shared.info("Optimistically updated \(issueKey) to backlog in local cache")
                        }
                    }

                    return true
                } else {
                    if let errorMessage = String(data: data, encoding: .utf8) {
                        Logger.shared.error("Error moving to backlog: \(errorMessage)")
                    }
                    return false
                }
            } catch {
                Logger.shared.error("Failed to move issue to backlog: \(error)")
                return false
            }
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
                if let assigneeValue = value as? String {
                    // Check if it's the current user's email
                    if assigneeValue == config.jiraEmail, let accountId = currentUserAccountId {
                        jiraFields["assignee"] = ["accountId": accountId]
                        Logger.shared.info("Using current user accountId for assignee")
                    } else if assigneeValue.contains("@") {
                        // Looks like an email address - search for user
                        let users = await searchUsers(query: assigneeValue)
                        if let user = users.first(where: { $0.email.lowercased() == assigneeValue.lowercased() }) {
                            jiraFields["assignee"] = ["accountId": user.accountId]
                            Logger.shared.info("Found user by email '\(assigneeValue)': \(user.displayName) (\(user.accountId))")
                        } else if let user = users.first {
                            jiraFields["assignee"] = ["accountId": user.accountId]
                            Logger.shared.info("Using first search result for '\(assigneeValue)': \(user.displayName) (\(user.accountId))")
                        } else {
                            Logger.shared.warning("Could not find user with email: \(assigneeValue)")
                        }
                    } else {
                        // Assume it's a display name - search for user
                        let users = await searchUsers(query: assigneeValue)
                        if let user = users.first(where: { $0.displayName.lowercased() == assigneeValue.lowercased() }) {
                            jiraFields["assignee"] = ["accountId": user.accountId]
                            Logger.shared.info("Found user by exact name '\(assigneeValue)': \(user.displayName) (\(user.accountId))")
                        } else if let user = users.first {
                            // Use best match from search
                            jiraFields["assignee"] = ["accountId": user.accountId]
                            Logger.shared.info("Using first search result for '\(assigneeValue)': \(user.displayName) (\(user.accountId))")
                        } else {
                            Logger.shared.warning("Could not find user matching: \(assigneeValue)")
                        }
                    }
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

    func addComment(issueKey: String, comment: String, parentId: String? = nil) async -> Bool {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/comment"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for adding comment")
            return false
        }

        var request = createRequest(url: url)
        request.httpMethod = "POST"

        // Parse comment text and convert mentions to ADF format
        let paragraphContent = await parseCommentWithMentions(comment)

        var requestBody: [String: Any] = [
            "body": [
                "type": "doc",
                "version": 1,
                "content": [
                    [
                        "type": "paragraph",
                        "content": paragraphContent
                    ]
                ]
            ]
        ]

        // Add parentId for threaded replies
        if let parentId = parentId {
            requestBody["parentId"] = parentId
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            // Log the request body for debugging
            if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                Logger.shared.info("Comment request body: \(jsonString)")
            }

            Logger.shared.info("Adding comment to \(issueKey)\(parentId != nil ? " (reply to \(parentId!))" : "")")

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

    func fetchChangelog(issueKey: String) async -> (success: Bool, changelog: String?) {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/changelog"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for fetching changelog")
            return (false, nil)
        }

        let request = createRequest(url: url)

        do {
            Logger.shared.info("Fetching changelog for \(issueKey)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Changelog response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                // Parse the changelog
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let values = json["values"] as? [[String: Any]] {

                    var changelogText = "Change History for \(issueKey):\n\n"

                    for change in values.reversed() { // Reverse to show oldest first
                        // Extract timestamp
                        if let created = change["created"] as? String {
                            changelogText += "• \(formatChangelogDate(created))\n"
                        }

                        // Extract author
                        if let author = change["author"] as? [String: Any],
                           let displayName = author["displayName"] as? String {
                            changelogText += "  By: \(displayName)\n"
                        }

                        // Extract items (field changes)
                        if let items = change["items"] as? [[String: Any]] {
                            for item in items {
                                let field = item["field"] as? String ?? "Unknown"
                                let from = item["fromString"] as? String ?? "(none)"
                                let to = item["toString"] as? String ?? "(none)"

                                changelogText += "  Changed \(field): \(from) → \(to)\n"
                            }
                        }

                        changelogText += "\n"
                    }

                    Logger.shared.info("Successfully fetched changelog for \(issueKey)")
                    return (true, changelogText)
                } else {
                    return (true, "No changelog entries found for \(issueKey)")
                }
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error fetching changelog: \(errorMessage)")
                }
                return (false, nil)
            }
        } catch {
            Logger.shared.error("Failed to fetch changelog: \(error)")
            return (false, nil)
        }
    }

    private func formatChangelogDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: isoString) else {
            return isoString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }

    func fetchIssueDetails(issueKey: String) async -> (success: Bool, details: IssueDetails?) {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for fetching issue details")
            return (false, nil)
        }

        let request = createRequest(url: url)

        do {
            Logger.shared.info("Fetching full details for \(issueKey)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Issue details response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let issue = try decoder.decode(JiraIssue.self, from: data)

                // Extract description from raw JSON (it's in ADF format)
                var descriptionText: String? = nil
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let fields = json["fields"] as? [String: Any],
                   let descriptionADF = fields["description"] as? [String: Any] {
                    descriptionText = extractTextFromADF(descriptionADF)
                }

                // Also fetch comments and changelog
                async let commentsResult = fetchComments(issueKey: issueKey)
                async let changelogResult = fetchChangelog(issueKey: issueKey)

                let comments = await commentsResult
                let changelog = await changelogResult

                let details = IssueDetails(
                    issue: issue,
                    description: descriptionText,
                    comments: comments.comments ?? [],
                    changelog: changelog.changelog ?? "No changelog available"
                )

                Logger.shared.info("Successfully fetched details for \(issueKey)")
                return (true, details)
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error fetching issue details: \(errorMessage)")
                }
                return (false, nil)
            }
        } catch {
            Logger.shared.error("Failed to fetch issue details: \(error)")
            return (false, nil)
        }
    }

    func fetchChildIssues(jql: String) async -> [JiraIssue] {
        var components = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search/jql")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "fields", value: "summary,status,resolution,assignee,issuetype,project,priority,created,updated,components,customfield_10014,customfield_10016,customfield_10020,timeoriginalestimate,timespent,timeestimate")
        ]

        guard let url = components.url else {
            Logger.shared.error("Invalid URL for fetching child issues")
            return []
        }

        let request = createRequest(url: url)

        do {
            Logger.shared.info("Fetching child issues with JQL: \(jql)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Child issues response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                let searchResponse = try JSONDecoder().decode(JiraSearchResponse.self, from: data)
                Logger.shared.info("Found \(searchResponse.issues.count) child issues")
                return searchResponse.issues
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error fetching child issues: \(errorMessage)")
                }
                return []
            }
        } catch {
            Logger.shared.error("Failed to fetch child issues: \(error)")
            return []
        }
    }

    func fetchComments(issueKey: String) async -> (success: Bool, comments: [IssueComment]?) {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/\(issueKey)/comment?expand=properties"

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL for fetching comments")
            return (false, nil)
        }

        let request = createRequest(url: url)

        do {
            Logger.shared.info("Fetching comments for \(issueKey)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let commentsArray = json["comments"] as? [[String: Any]] {

                    var comments: [IssueComment] = []

                    for commentDict in commentsArray {
                        if let id = commentDict["id"] as? String,
                           let author = commentDict["author"] as? [String: Any],
                           let authorName = author["displayName"] as? String,
                           let created = commentDict["created"] as? String,
                           let body = commentDict["body"] as? [String: Any] {

                            // Extract plain text from ADF (Atlassian Document Format)
                            let bodyText = extractTextFromADF(body)

                            // Get parentId for threaded comments (optional field)
                            // parentId can be String or Int depending on Jira version
                            var parentId: String? = nil
                            if let parentIdStr = commentDict["parentId"] as? String {
                                parentId = parentIdStr
                            } else if let parentIdInt = commentDict["parentId"] as? Int {
                                parentId = String(parentIdInt)
                            }

                            let comment = IssueComment(
                                id: id,
                                author: authorName,
                                created: created,
                                body: bodyText,
                                parentId: parentId
                            )
                            comments.append(comment)
                        }
                    }

                    Logger.shared.info("Successfully fetched \(comments.count) comments for \(issueKey)")
                    return (true, comments)
                }
                return (true, [])
            } else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Error fetching comments: \(errorMessage)")
                }
                return (false, nil)
            }
        } catch {
            Logger.shared.error("Failed to fetch comments: \(error)")
            return (false, nil)
        }
    }

    private func parseCommentWithMentions(_ comment: String) async -> [[String: Any]] {
        Logger.shared.info("Parsing comment for mentions: \(comment)")
        var content: [[String: Any]] = []
        var currentText = ""
        var i = comment.startIndex

        while i < comment.endIndex {
            if comment[i] == "@" {
                // Save any accumulated text before the mention
                if !currentText.isEmpty {
                    content.append([
                        "type": "text",
                        "text": currentText
                    ])
                    currentText = ""
                }

                // Extract potential mention text - try progressively longer strings
                // Start with everything until the next @ or end of string
                var searchEnd = comment.index(after: i)
                while searchEnd < comment.endIndex && comment[searchEnd] != "@" {
                    searchEnd = comment.index(after: searchEnd)
                }

                let potentialMentionArea = String(comment[comment.index(after: i)..<searchEnd])

                // Try to find the longest matching user name starting from @
                var bestMatch: (displayName: String, accountId: String, endIndex: String.Index)?

                // Search for users with the first word(s) after @
                let words = potentialMentionArea.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                for wordCount in (1...min(words.count, 5)).reversed() {
                    let candidateName = words.prefix(wordCount).joined(separator: " ")
                    Logger.shared.info("Trying to match: '\(candidateName)'")

                    let users = await searchUsers(query: candidateName)
                    if let user = users.first(where: { $0.displayName.lowercased() == candidateName.lowercased() }) {
                        let mentionEnd = comment.index(i, offsetBy: candidateName.count + 1)
                        bestMatch = (user.displayName, user.accountId, mentionEnd)
                        Logger.shared.info("Found match: \(user.displayName) (accountId: \(user.accountId))")
                        break
                    }
                }

                if let match = bestMatch {
                    // Add proper mention node
                    content.append([
                        "type": "mention",
                        "attrs": [
                            "id": match.accountId,
                            "text": "@\(match.displayName)"
                        ]
                    ])
                    i = match.endIndex
                } else {
                    // No match found - just include @ and continue
                    Logger.shared.warning("No match found for mentions starting at @")
                    currentText.append("@")
                    i = comment.index(after: i)
                }
            } else {
                currentText.append(comment[i])
                i = comment.index(after: i)
            }
        }

        // Add any remaining text
        if !currentText.isEmpty {
            content.append([
                "type": "text",
                "text": currentText
            ])
        }

        return content.isEmpty ? [["type": "text", "text": comment]] : content
    }

    private func extractTextFromADF(_ adf: [String: Any]) -> String {
        guard let content = adf["content"] as? [[String: Any]] else {
            return ""
        }

        var text = ""
        for node in content {
            if let nodeType = node["type"] as? String {
                if nodeType == "paragraph" {
                    if let paragraphContent = node["content"] as? [[String: Any]] {
                        for textNode in paragraphContent {
                            let type = textNode["type"] as? String
                            if type == "text", let nodeText = textNode["text"] as? String {
                                text += nodeText
                            } else if type == "mention",
                                      let attrs = textNode["attrs"] as? [String: Any],
                                      let mentionText = attrs["text"] as? String {
                                // Render mentions with their display text
                                text += mentionText
                            }
                        }
                    }
                    text += "\n"
                }
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchCreateMetadata(projectKey: String, issueType: String = "Story") async -> [String: Any]? {
        let urlString = "\(config.jiraBaseURL)/rest/api/3/issue/createmeta?projectKeys=\(projectKey)&issuetypeNames=\(issueType)&expand=projects.issuetypes.fields"

        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else {
            Logger.shared.error("Invalid URL for fetching create metadata")
            return nil
        }

        let request = createRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            Logger.shared.info("Fetch create metadata response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]],
               let project = projects.first,
               let issuetypes = project["issuetypes"] as? [[String: Any]],
               let issuetype = issuetypes.first,
               let fields = issuetype["fields"] as? [String: Any] {

                Logger.shared.info("Fetched \(fields.count) field definitions for \(projectKey)/\(issueType)")
                return fields
            } else {
                Logger.shared.error("Failed to parse create metadata")
                if let jsonString = String(data: data, encoding: .utf8) {
                    Logger.shared.error("Response: \(jsonString.prefix(500))")
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch create metadata: \(error)")
        }

        return nil
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

        // Required: Project (accept both string and dict format)
        if let projectDict = fields["project"] as? [String: Any] {
            // Already in Jira format
            jiraFields["project"] = projectDict
        } else if let projectValue = fields["project"] as? String {
            // Check if this is a project name that needs to be converted to a key
            // LLM might return full project name instead of key
            if let projectKey = projectNameToKey[projectValue] {
                // It's a project name - convert to key
                Logger.shared.info("Converted project name '\(projectValue)' to key '\(projectKey)'")
                jiraFields["project"] = ["key": projectKey]
            } else if availableProjects.contains(where: { $0.key == projectValue }) {
                // It's already a valid project key
                jiraFields["project"] = ["key": projectValue]
            } else {
                // Assume it's a key and let Jira validate
                Logger.shared.warning("Project '\(projectValue)' not found in name-to-key map or known projects, using as-is")
                jiraFields["project"] = ["key": projectValue]
            }
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

        // Required: Issue Type (accept both string and dict format)
        if let issueTypeDict = fields["issuetype"] as? [String: Any] {
            jiraFields["issuetype"] = issueTypeDict
        } else if let issueType = fields["type"] as? String {
            jiraFields["issuetype"] = ["name": issueType]
        } else {
            // Default to Story if not specified
            jiraFields["issuetype"] = ["name": "Story"]
        }

        // Optional: Assignee (accept both string and dict format)
        if let assigneeDict = fields["assignee"] as? [String: Any] {
            // Check if it's the current user and we have accountId
            if let name = assigneeDict["name"] as? String,
               name == config.jiraEmail,
               let accountId = currentUserAccountId {
                jiraFields["assignee"] = ["accountId": accountId]
                Logger.shared.info("Using accountId for assignee: \(accountId)")
            } else {
                // Use the dict as-is
                jiraFields["assignee"] = assigneeDict
            }
        } else if let assignee = fields["assignee"] as? String {
            // Check if this is the current user
            if assignee == config.jiraEmail, let accountId = currentUserAccountId {
                // Use accountId for current user
                jiraFields["assignee"] = ["accountId": accountId]
                Logger.shared.info("Using accountId for assignee: \(accountId)")
            } else {
                // For other users, try email
                jiraFields["assignee"] = ["emailAddress": assignee]
                Logger.shared.info("Using email for assignee: \(assignee)")
            }
        }

        // Optional: Original Estimate (accept dict format from LLM or simple string)
        if let timetrackingDict = fields["timetracking"] as? [String: Any] {
            jiraFields["timetracking"] = timetrackingDict
        } else if let estimateStr = (fields["originalEstimate"] as? String) ?? (fields["estimate"] as? String) {
            // Convert "1.5h" or "1h 30m" to Jira format
            jiraFields["timetracking"] = ["originalEstimate": estimateStr]
        }

        // Helper to get project key from jiraFields (which has already been resolved)
        let resolvedProjectKey: String? = {
            if let projectDict = jiraFields["project"] as? [String: Any] {
                return projectDict["key"] as? String
            }
            return nil
        }()

        // Optional: Sprint (accept customfield_10020 directly or resolve from sprint name)
        if let customfieldValue = fields["customfield_10020"] {
            if let sprintString = customfieldValue as? String, sprintString.lowercased() == "current" {
                // Resolve "current" to actual sprint ID
                let activeSprint = await findActiveSprintForProject(projectKey: resolvedProjectKey)
                if let sprint = activeSprint {
                    jiraFields["customfield_10020"] = sprint.id
                    Logger.shared.info("Using current sprint for project \(resolvedProjectKey ?? "unknown"): \(sprint.name) (ID: \(sprint.id))")
                } else {
                    Logger.shared.warning("Could not find active sprint for project: \(resolvedProjectKey ?? "unknown")")
                }
            } else {
                // Already an ID or other value, use as-is
                jiraFields["customfield_10020"] = customfieldValue
            }
        } else if let sprintValue = fields["sprint"] as? String {
            if sprintValue.lowercased() == "current" {
                // Find the currently active sprint for this project
                let activeSprint = await findActiveSprintForProject(projectKey: resolvedProjectKey)

                if let sprint = activeSprint {
                    jiraFields["customfield_10020"] = sprint.id
                    Logger.shared.info("Using current sprint for project \(resolvedProjectKey ?? "unknown"): \(sprint.name) (ID: \(sprint.id))")
                } else {
                    Logger.shared.warning("Could not find active sprint for project: \(resolvedProjectKey ?? "unknown")")
                }
            } else {
                // Try to find sprint by name (optionally scoped to project)
                let matchingSprint = await findSprintByName(sprintValue, projectKey: resolvedProjectKey)
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
            // Try to find epic by semantic search (scoped to the target project)
            let matchingEpic = await findEpicByName(epicQuery, projectKey: resolvedProjectKey)
            if let epicKey = matchingEpic {
                jiraFields["customfield_10014"] = epicKey
                Logger.shared.info("Matched epic '\(epicQuery)' to: \(epicKey)")
            } else {
                // Fallback to using it as-is (might be exact epic key)
                jiraFields["customfield_10014"] = epicQuery
                Logger.shared.warning("Could not find epic matching '\(epicQuery)', using as-is")
            }
        }

        // Optional: Components (accept array of dicts or array of strings)
        if let componentsArray = fields["components"] as? [[String: Any]] {
            // Already in Jira format
            jiraFields["components"] = componentsArray
        } else if let components = fields["components"] as? [String] {
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

        // Optional: Reporter (accept dict format from LLM, fix to use accountId)
        if let reporterDict = fields["reporter"] as? [String: Any] {
            // Check if it's the current user and we have accountId
            if let name = reporterDict["name"] as? String,
               name == config.jiraEmail,
               let accountId = currentUserAccountId {
                jiraFields["reporter"] = ["accountId": accountId]
                Logger.shared.info("Using accountId for reporter: \(accountId)")
            } else {
                // Use the dict as-is (but this might fail)
                jiraFields["reporter"] = reporterDict
            }
        } else if let reporter = fields["reporter"] as? String {
            // Check if this is the current user
            if reporter == config.jiraEmail, let accountId = currentUserAccountId {
                jiraFields["reporter"] = ["accountId": accountId]
                Logger.shared.info("Using accountId for reporter: \(accountId)")
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

    func findActiveSprintsForProject(projectKey: String?) async -> [JiraSprint] {
        guard let projectKey = projectKey else {
            Logger.shared.warning("No project key provided for finding active sprints")
            return []
        }

        // Query for all boards belonging to this project
        let urlString = "\(config.jiraBaseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)"
        guard let url = URL(string: urlString) else { return [] }

        let request = createRequest(url: url)
        var projectBoardIds: [Int] = []

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let boards = json["values"] as? [[String: Any]] {

                // Filter to only Scrum boards (Kanban boards don't have sprints)
                for board in boards {
                    if let boardId = board["id"] as? Int,
                       let boardType = board["type"] as? String,
                       boardType.lowercased() == "scrum" {
                        projectBoardIds.append(boardId)
                    }
                }

                Logger.shared.info("Found \(projectBoardIds.count) Scrum boards for project \(projectKey): \(projectBoardIds)")
            }
        } catch {
            Logger.shared.error("Failed to fetch boards for project \(projectKey): \(error)")
        }

        // Fetch sprints directly from the project's boards
        var activeProjectSprints: [JiraSprint] = []

        for boardId in projectBoardIds {
            let boardSprints = await fetchSprintsForBoard(boardId: boardId)

            // Filter to only active sprints
            let activeSprints = boardSprints.filter { $0.state.lowercased() == "active" }

            Logger.shared.info("Board \(boardId) has \(activeSprints.count) active sprint(s)")

            activeProjectSprints.append(contentsOf: activeSprints)
        }

        if activeProjectSprints.isEmpty {
            Logger.shared.warning("No active sprints found for project \(projectKey)")
        } else {
            Logger.shared.info("Found \(activeProjectSprints.count) active sprint(s) for project \(projectKey): \(activeProjectSprints.map { $0.name }.joined(separator: ", "))")
        }

        return activeProjectSprints
    }

    func findActiveSprintForProject(projectKey: String?) async -> JiraSprint? {
        let sprints = await findActiveSprintsForProject(projectKey: projectKey)
        return sprints.first
    }

    func findSprintByName(_ query: String, projectKey: String? = nil) async -> JiraSprint? {
        var sprints = await MainActor.run { self.availableSprints }

        // If projectKey is provided, try to filter sprints to that project's board first
        if let projectKey = projectKey {
            let projectSprints = await fetchSprintsForProject(projectKey: projectKey)
            if !projectSprints.isEmpty {
                sprints = projectSprints
                Logger.shared.info("Searching for sprint '\(query)' in project \(projectKey) (\(sprints.count) sprints)")
            }
        }

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

    private func fetchSprintsForProject(projectKey: String) async -> [JiraSprint] {
        let urlString = "\(config.jiraBaseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)"
        guard let url = URL(string: urlString) else { return [] }

        let request = createRequest(url: url)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let boards = json["values"] as? [[String: Any]],
               let firstBoard = boards.first,
               let boardId = firstBoard["id"] as? Int {

                return await fetchSprintsForBoard(boardId: boardId)
            }
        } catch {
            Logger.shared.error("Failed to fetch sprints for project \(projectKey): \(error)")
        }

        return []
    }

    func findEpicByName(_ query: String, projectKey: String? = nil) async -> String? {
        // First, search in currently loaded epics
        let summaries = await MainActor.run { self.epicSummaries }
        let lowercaseQuery = query.lowercased()

        Logger.shared.info("Searching for epic matching query: '\(query)' in project: \(projectKey ?? "any")")
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
        return await searchAllEpicsInProject(query: query, queryWords: queryWords, projectKey: projectKey)
    }

    private func searchAllEpicsInProject(query: String, queryWords: [String], projectKey: String? = nil) async -> String? {
        // Get the project to search - either explicit or from current filters
        let projects: [String]
        if let pk = projectKey {
            projects = [pk]
        } else {
            projects = await MainActor.run { Array(self.filters.projects) }
        }

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

    // MARK: - Helper Functions

    private func stripHTMLTags(from string: String) -> String {
        // Remove HTML tags like <b>, </b>, <em>, </em>, etc.
        var result = string
        let pattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: ""
            )
        }

        // Clean up multiple spaces left after tag removal
        let spacePattern = " +"
        if let spaceRegex = try? NSRegularExpression(pattern: spacePattern, options: []) {
            result = spaceRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: " "
            )
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
