import Foundation

struct SavedView: Identifiable, Codable {
    let id: UUID
    var name: String
    let filters: PersistedFilters
    let jql: String? // Store original JQL if created from JQL search
    let createdAt: Date

    init(id: UUID = UUID(), name: String, filters: PersistedFilters, jql: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.filters = filters
        self.jql = jql
        self.createdAt = createdAt
    }
}

class ViewsManager: ObservableObject {
    @Published var savedViews: [SavedView] = []
    @Published var currentViewID: UUID?

    private let maxViews = 20
    private let storageKey = "savedViews"

    init() {
        loadViews()

        // Listen for manual filter changes to clear current view
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClearCurrentView"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Defer the state update to avoid modifying @Published during view updates
            DispatchQueue.main.async {
                self?.clearCurrentView()
            }
        }
    }

    func loadViews() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedView].self, from: data) {
            savedViews = decoded
            Logger.shared.info("Loaded \(decoded.count) saved views")
        }
    }

    func saveViews() {
        if let encoded = try? JSONEncoder().encode(savedViews) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            Logger.shared.info("Saved \(savedViews.count) views")
        }
    }

    func addView(name: String, filters: PersistedFilters, jql: String? = nil) -> Bool {
        guard savedViews.count < maxViews else {
            Logger.shared.warning("Cannot add view: maximum of \(maxViews) views reached")
            return false
        }

        Logger.shared.info("Creating view '\(name)' with filters:")
        Logger.shared.info("  Projects: \(filters.projects)")
        Logger.shared.info("  Statuses: \(filters.statuses)")
        Logger.shared.info("  Assignees: \(filters.assignees)")
        Logger.shared.info("  Issue Types: \(filters.issueTypes)")
        if let jql = jql {
            Logger.shared.info("  Original JQL: \(jql)")
        }

        let newView = SavedView(name: name, filters: filters, jql: jql)
        savedViews.append(newView)
        savedViews.sort { $0.name.lowercased() < $1.name.lowercased() }
        saveViews()
        currentViewID = newView.id
        Logger.shared.info("Added new view: \(name)")
        return true
    }

    func updateView(id: UUID, name: String) {
        if let index = savedViews.firstIndex(where: { $0.id == id }) {
            savedViews[index].name = name
            savedViews.sort { $0.name.lowercased() < $1.name.lowercased() }
            saveViews()
            Logger.shared.info("Updated view: \(name)")
        }
    }

    func deleteView(id: UUID) {
        savedViews.removeAll { $0.id == id }
        if currentViewID == id {
            currentViewID = nil
        }
        saveViews()
        Logger.shared.info("Deleted view with ID: \(id)")
    }

    func applyView(_ view: SavedView, to jiraService: JiraService) {
        Logger.shared.info("Applying view '\(view.name)' with filters:")
        Logger.shared.info("  Projects: \(view.filters.projects)")
        Logger.shared.info("  Statuses: \(view.filters.statuses)")
        Logger.shared.info("  Assignees: \(view.filters.assignees)")
        Logger.shared.info("  Issue Types: \(view.filters.issueTypes)")
        if let jql = view.jql {
            Logger.shared.info("  Using stored JQL: \(jql)")
        }

        // If view has stored JQL, use that directly instead of filters
        if let jql = view.jql {
            Task {
                await jiraService.searchWithJQL(jql)
            }
        } else {
            // Otherwise apply filters normally
            jiraService.filters.projects = Set(view.filters.projects)
            jiraService.filters.statuses = Set(view.filters.statuses)
            jiraService.filters.assignees = Set(view.filters.assignees)
            jiraService.filters.issueTypes = Set(view.filters.issueTypes)
            jiraService.filters.epics = Set(view.filters.epics)
            jiraService.filters.sprints = Set(view.filters.sprints)
            jiraService.filters.showOnlyMyIssues = view.filters.showOnlyMyIssues

            jiraService.saveFilters()
            jiraService.applyFilters(updateOptions: true, fromSavedView: true)
        }

        currentViewID = view.id
        Logger.shared.info("Applied view: \(view.name)")
    }

    func clearCurrentView() {
        currentViewID = nil
    }

    var currentView: SavedView? {
        guard let id = currentViewID else { return nil }
        return savedViews.first { $0.id == id }
    }
}
