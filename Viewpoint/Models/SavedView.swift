import Foundation

struct SavedView: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let filters: PersistedFilters
    let createdAt: Date

    init(id: UUID = UUID(), name: String, filters: PersistedFilters, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.filters = filters
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
            self?.clearCurrentView()
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

    func addView(name: String, filters: PersistedFilters) -> Bool {
        guard savedViews.count < maxViews else {
            Logger.shared.warning("Cannot add view: maximum of \(maxViews) views reached")
            return false
        }

        let newView = SavedView(name: name, filters: filters)
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
        jiraService.filters.projects = Set(view.filters.projects)
        jiraService.filters.statuses = Set(view.filters.statuses)
        jiraService.filters.assignees = Set(view.filters.assignees)
        jiraService.filters.issueTypes = Set(view.filters.issueTypes)
        jiraService.filters.epics = Set(view.filters.epics)
        jiraService.filters.sprints = Set(view.filters.sprints)
        jiraService.filters.showOnlyMyIssues = view.filters.showOnlyMyIssues

        currentViewID = view.id
        jiraService.saveFilters()
        jiraService.applyFilters(updateOptions: true, fromSavedView: true)

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
