import SwiftUI

struct ContentView: View {
    @EnvironmentObject var jiraService: JiraService
    @EnvironmentObject var viewsManager: ViewsManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showFilters") private var showFilters: Bool = true
    @AppStorage("sortOption") private var sortOptionRaw: String = "dateCreated"
    @AppStorage("sortDirection") private var sortDirectionRaw: String = "descending"
    @AppStorage("groupOption") private var groupOptionRaw: String = "none"
    @AppStorage("textSize") private var textSize: Double = 1.0
    @AppStorage("filterPanelHeight") private var filterPanelHeight: Double = 200
    @State private var showingLogWorkForSelected = false
    @State private var showingSaveViewDialog = false
    @State private var showingManageViewsSheet = false
    @State private var showingCreateIssue = false
    @State private var newViewName = ""
    @AppStorage("colorScheme") private var colorSchemePreference: String = "auto"
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @AppStorage("expandedSectionsRaw") private var expandedSectionsRaw: String = ""
    @AppStorage("clientCreatedFilter") private var clientCreatedFilterRaw: String = "all"
    @AppStorage("clientTypeFilter") private var clientTypeFilterRaw: String = "all"
    @AppStorage("clientStatusFilter") private var clientStatusFilterRaw: String = "all"

    private var clientCreatedFilter: CreatedFilter {
        CreatedFilter(rawValue: clientCreatedFilterRaw) ?? .all
    }

    private var clientTypeFilter: String {
        clientTypeFilterRaw
    }

    private var clientStatusFilter: String {
        clientStatusFilterRaw
    }

    private var expandedSections: Binding<Set<String>> {
        Binding(
            get: {
                guard !expandedSectionsRaw.isEmpty else { return [] }
                return Set(expandedSectionsRaw.split(separator: ",").map(String.init))
            },
            set: { newValue in
                expandedSectionsRaw = newValue.sorted().joined(separator: ",")
            }
        )
    }

    private var sortOption: SortOption {
        SortOption.allCases.first { $0.rawValue == sortOptionRaw } ?? .dateCreated
    }

    private var sortDirection: SortDirection {
        sortDirectionRaw == "ascending" ? .ascending : .descending
    }

    private var groupOption: GroupOption {
        GroupOption.allCases.first { $0.rawValue == groupOptionRaw } ?? .none
    }

    private var colorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // Get the first selected issue for single-issue operations
    private var primarySelectedIssue: JiraIssue? {
        guard let firstID = jiraService.selectedIssues.first else { return nil }
        return jiraService.issues.first { $0.id == firstID }
    }

    var filteredIssues: [JiraIssue] {
        var issues = jiraService.issues

        // Apply search filter
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            issues = issues.filter { issue in
                issue.key.lowercased().contains(lowercasedSearch) ||
                issue.summary.lowercased().contains(lowercasedSearch)
            }
        }

        // Apply client-side created date filter
        if clientCreatedFilter != .all {
            let cutoffDate = clientCreatedFilter.cutoffDate
            issues = issues.filter { issue in
                guard let created = issue.created else { return false }
                return created >= cutoffDate
            }
        }

        // Apply client-side type filter
        if clientTypeFilter != "all" {
            issues = issues.filter { $0.issueType == clientTypeFilter }
        }

        // Apply client-side status filter
        if clientStatusFilter != "all" {
            issues = issues.filter { $0.status == clientStatusFilter }
        }

        return issues
    }

    var sortedIssues: [JiraIssue] {
        let sorted = filteredIssues.sorted { issue1, issue2 in
            let ascending = sortDirection == .ascending
            switch sortOption {
            case .status:
                return ascending ? issue1.status < issue2.status : issue1.status > issue2.status
            case .dateCreated:
                let date1 = issue1.created ?? Date.distantPast
                let date2 = issue2.created ?? Date.distantPast
                return ascending ? date1 < date2 : date1 > date2
            case .dateUpdated:
                let date1 = issue1.updated ?? Date.distantPast
                let date2 = issue2.updated ?? Date.distantPast
                return ascending ? date1 < date2 : date1 > date2
            case .assignee:
                let assignee1 = issue1.assignee ?? ""
                let assignee2 = issue2.assignee ?? ""
                return ascending ? assignee1 < assignee2 : assignee1 > assignee2
            case .epic:
                let epic1 = issue1.epic ?? ""
                let epic2 = issue2.epic ?? ""
                return ascending ? epic1 < epic2 : epic1 > epic2
            }
        }

        return sorted
    }

    var groupedIssues: [(String, [JiraIssue])] {
        if groupOption == .none {
            return [("All Issues", sortedIssues)]
        }

        let grouped = Dictionary(grouping: sortedIssues) { issue -> String in
            switch groupOption {
            case .none:
                return "All Issues"
            case .assignee:
                return issue.assignee ?? "Unassigned"
            case .status:
                return issue.status
            case .epic:
                if let epicKey = issue.fields.customfield_10014 {
                    if let epicSummary = jiraService.epicSummaries[epicKey] {
                        return "\(epicKey): \(epicSummary)"
                    }
                    return epicKey
                }
                return "No Epic"
            case .initiative:
                // For now, use project as initiative placeholder
                return issue.project
            }
        }

        // Sort groups by name, and sort issues within each group
        return grouped.sorted { $0.key < $1.key }.map { (key, issues) in
            let sortedGroupIssues = issues.sorted { issue1, issue2 in
                let ascending = sortDirection == .ascending
                switch sortOption {
                case .status:
                    return ascending ? issue1.status < issue2.status : issue1.status > issue2.status
                case .dateCreated:
                    let date1 = issue1.created ?? Date.distantPast
                    let date2 = issue2.created ?? Date.distantPast
                    return ascending ? date1 < date2 : date1 > date2
                case .dateUpdated:
                    let date1 = issue1.updated ?? Date.distantPast
                    let date2 = issue2.updated ?? Date.distantPast
                    return ascending ? date1 < date2 : date1 > date2
                case .assignee:
                    let assignee1 = issue1.assignee ?? ""
                    let assignee2 = issue2.assignee ?? ""
                    return ascending ? assignee1 < assignee2 : assignee1 > assignee2
                case .epic:
                    let epic1 = issue1.epic ?? ""
                    let epic2 = issue2.epic ?? ""
                    return ascending ? epic1 < epic2 : epic1 > epic2
                }
            }
            return (key, sortedGroupIssues)
        }
    }

    var issueContentView: some View {
        VStack(spacing: 0) {
            // Secondary toolbar for list controls
            IssueListToolbar(
                searchText: $searchText,
                isSearchFocused: $isSearchFocused,
                sortOption: sortOption,
                sortDirection: sortDirection,
                groupOption: groupOption,
                groupedIssues: groupedIssues,
                totalIssueCount: groupedIssues.reduce(0) { $0 + $1.1.count },
                expandedSections: expandedSections,
                onSortOptionChange: { sortOptionRaw = $0.rawValue },
                onSortDirectionChange: { sortDirectionRaw = $0 == .ascending ? "ascending" : "descending" },
                onGroupOptionChange: { groupOptionRaw = $0.rawValue },
                clientCreatedFilter: clientCreatedFilter,
                onCreatedFilterChange: { clientCreatedFilterRaw = $0.rawValue },
                clientTypeFilter: clientTypeFilter,
                onTypeFilterChange: { clientTypeFilterRaw = $0 },
                clientStatusFilter: clientStatusFilter,
                onStatusFilterChange: { clientStatusFilterRaw = $0 }
            )

            // Issue list content
            Group {
                if jiraService.isLoading {
                    ProgressView("Loading issues...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = jiraService.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    IssueListView(selectedIssues: $jiraService.selectedIssues, groupedIssues: groupedIssues, expandedSections: expandedSections, groupOption: groupOption)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and refresh
            HeaderView(filteredCount: filteredIssues.count, searchText: searchText)

            // Split view with resizable divider
            if showFilters {
                PersistentSplitView(
                    top: FilterPanel(),
                    bottom: issueContentView,
                    position: $filterPanelHeight
                )
            } else {
                issueContentView
            }

            // Status bar at the bottom
            StatusBarView()
        }
        .sheet(isPresented: $showingLogWorkForSelected) {
            if let issue = primarySelectedIssue {
                LogWorkView(issue: issue, isPresented: $showingLogWorkForSelected)
            }
        }
        .sheet(isPresented: $showingSaveViewDialog) {
            SaveViewDialog(
                viewName: $newViewName,
                isPresented: $showingSaveViewDialog,
                onSave: { name in
                    let currentFilters = PersistedFilters(
                        projects: Array(jiraService.filters.projects),
                        statuses: Array(jiraService.filters.statuses),
                        assignees: Array(jiraService.filters.assignees),
                        issueTypes: Array(jiraService.filters.issueTypes),
                        epics: Array(jiraService.filters.epics),
                        sprints: Array(jiraService.filters.sprints),
                        showOnlyMyIssues: jiraService.filters.showOnlyMyIssues
                    )

                    if viewsManager.addView(name: name, filters: currentFilters) {
                        showingSaveViewDialog = false
                    }
                }
            )
        }
        .sheet(isPresented: $showingManageViewsSheet) {
            ManageViewsSheet(isPresented: $showingManageViewsSheet)
                .environmentObject(viewsManager)
        }
        .sheet(isPresented: $showingCreateIssue) {
            QuickCreateIssueView(isPresented: $showingCreateIssue)
                .environmentObject(jiraService)
                .frame(width: 400, height: 150)
        }
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "toggleFilters", placement: .navigation, showsByDefault: true) {
                Button(action: { showFilters.toggle() }) {
                    Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                }
            }

            ToolbarItem(id: "views", placement: .automatic, showsByDefault: true) {
                Menu {
                    // List saved views
                    if !viewsManager.savedViews.isEmpty {
                        ForEach(viewsManager.savedViews) { view in
                            Button(action: {
                                viewsManager.applyView(view, to: jiraService)
                            }) {
                                HStack {
                                    Text(view.name)
                                    if viewsManager.currentViewID == view.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Divider()
                    }

                    Button("Save Current View...") {
                        newViewName = ""
                        showingSaveViewDialog = true
                    }

                    Button("Manage Views...") {
                        showingManageViewsSheet = true
                    }
                    .disabled(viewsManager.savedViews.isEmpty)
                } label: {
                    Label("Views", systemImage: "rectangle.stack")
                }
                .help("Manage saved filter views")
            }

            ToolbarItem(id: "createIssue", placement: .automatic, showsByDefault: true) {
                // Create new issue
                Button(action: {
                    showingCreateIssue = true
                }) {
                    Image(systemName: "plus.circle.fill")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Create new issue (⌘N)")
            }

            ToolbarItem(id: "logWork", placement: .automatic, showsByDefault: true) {
                // Log work for selected issue
                Button(action: {
                    if primarySelectedIssue != nil {
                        showingLogWorkForSelected = true
                    }
                }) {
                    Image(systemName: "clock.fill")
                }
                .keyboardShortcut("l", modifiers: .command)
                .help("Log work for selected issue (⌘L)")
                .disabled(primarySelectedIssue == nil)
            }

            ToolbarItem(id: "launchIndigo", placement: .automatic, showsByDefault: true) {
                // Launch Indigo AI Assistant
                Button(action: {
                    openWindow(id: "indigo")
                }) {
                    Label("Launch Indigo", systemImage: "waveform.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.46, green: 0.39, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Launch Indigo AI Assistant (⌘I)")
            }

            ToolbarItem(id: "controls", placement: .automatic, showsByDefault: true) {
                HStack(spacing: 12) {
                    // Dark mode toggle
                    Menu {
                        Button(action: { colorSchemePreference = "auto" }) {
                            HStack {
                                Text("Auto")
                                if colorSchemePreference == "auto" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Button(action: { colorSchemePreference = "light" }) {
                            HStack {
                                Text("Light")
                                if colorSchemePreference == "light" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Button(action: { colorSchemePreference = "dark" }) {
                            HStack {
                                Text("Dark")
                                if colorSchemePreference == "dark" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: colorSchemePreference == "dark" ? "moon.fill" : (colorSchemePreference == "light" ? "sun.max.fill" : "circle.lefthalf.filled"))
                    }
                    .help("Color scheme")

                    Divider()

                    // Text size controls
                    HStack(spacing: 4) {
                        Button(action: { textSize = max(0.8, textSize - 0.1) }) {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .help("Decrease text size")

                        Button(action: { textSize = min(1.5, textSize + 0.1) }) {
                            Image(systemName: "textformat.size.larger")
                        }
                        .help("Increase text size")
                    }

                    Divider()

                    // Refresh button
                    Button(action: { jiraService.refresh() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh issues")
                }
            }

            // Flexible space for customization
            ToolbarItem(id: "flexibleSpace", placement: .automatic, showsByDefault: false) {
                Spacer()
            }
        }
        .environment(\.textSizeMultiplier, textSize)
        .preferredColorScheme(colorScheme)
    }
}

// MARK: - Header View

struct HeaderView: View {
    @EnvironmentObject var jiraService: JiraService
    let filteredCount: Int
    let searchText: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Viewpoint")
                    .font(.title)
                    .fontWeight(.bold)
                if !searchText.isEmpty && filteredCount != jiraService.issues.count {
                    Text("\(filteredCount) of \(jiraService.issues.count) issues")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(jiraService.issues.count) issues")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Issue List View

struct IssueListView: View {
    @Binding var selectedIssues: Set<JiraIssue.ID>
    let groupedIssues: [(String, [JiraIssue])]
    @Binding var expandedSections: Set<String>
    let groupOption: GroupOption
    @EnvironmentObject var jiraService: JiraService
    @State private var draggedIssueKeys: Set<String> = []
    @State private var dropTargetGroup: String? = nil

    var body: some View {
        List(selection: $selectedIssues) {
            ForEach(groupedIssues, id: \.0) { groupName, issues in
                if groupedIssues.count > 1 {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSections.contains(groupName) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert(groupName)
                                } else {
                                    expandedSections.remove(groupName)
                                }
                            }
                        )
                    ) {
                        ForEach(issues) { issue in
                            IssueRow(issue: issue)
                                .tag(issue)
                                .onDrag {
                                    startDrag(issue: issue)
                                }
                        }
                    } label: {
                        HStack {
                            Text(groupName)
                                .font(.headline)
                                .textCase(.uppercase)
                                .foregroundColor(Color(red: 0.0, green: 0.4, blue: 0.2))
                            Spacer()
                            if !draggedIssueKeys.isEmpty {
                                Text("\(draggedIssueKeys.count) issue\(draggedIssueKeys.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(dropTargetGroup == groupName ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .onDrop(of: [.text], isTargeted: Binding(
                            get: { dropTargetGroup == groupName },
                            set: { isTargeted in
                                dropTargetGroup = isTargeted ? groupName : nil
                            }
                        )) { providers in
                            handleDrop(providers: providers, targetGroup: groupName)
                        }
                    }
                } else {
                    ForEach(issues) { issue in
                        IssueRow(issue: issue)
                            .tag(issue)
                            .onDrag {
                                startDrag(issue: issue)
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
        .onAppear {
            // Expand all sections by default on first appearance
            if expandedSections.isEmpty {
                expandedSections = Set(groupedIssues.map { $0.0 })
            }
        }
    }

    private func startDrag(issue: JiraIssue) -> NSItemProvider {
        // Determine which issues to drag
        var issuesToDrag: [JiraIssue]

        if selectedIssues.contains(issue.id) {
            // If the dragged issue is selected, drag all selected issues
            issuesToDrag = jiraService.issues.filter { selectedIssues.contains($0.id) }
        } else {
            // Otherwise, just drag this one issue
            issuesToDrag = [issue]
        }

        // Store the dragged issue keys for UI feedback
        draggedIssueKeys = Set(issuesToDrag.map { $0.key })

        // Create JSON payload with issue keys
        let issueKeys = issuesToDrag.map { $0.key }
        guard let jsonData = try? JSONEncoder().encode(issueKeys),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return NSItemProvider()
        }

        let provider = NSItemProvider(object: jsonString as NSString)
        return provider
    }

    private func handleDrop(providers: [NSItemProvider], targetGroup: String) -> Bool {
        guard let provider = providers.first else { return false }

        // Extract the JSON string from the provider
        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, error in
            guard error == nil,
                  let stringData = data as? Data,
                  let jsonString = String(data: stringData, encoding: .utf8),
                  let issueKeys = try? JSONDecoder().decode([String].self, from: Data(jsonString.utf8)) else {
                return
            }

            // Perform the bulk update on the main thread
            Task { @MainActor in
                await performBulkUpdate(issueKeys: issueKeys, targetGroup: targetGroup)
                draggedIssueKeys.removeAll()
            }
        }

        return true
    }

    private func performBulkUpdate(issueKeys: [String], targetGroup: String) async {
        switch groupOption {
        case .none:
            // No grouping, no bulk update
            break

        case .assignee:
            // targetGroup is the assignee display name
            await bulkUpdateAssignee(issueKeys: issueKeys, assignee: targetGroup)

        case .status:
            // targetGroup is the status name
            await bulkUpdateStatus(issueKeys: issueKeys, status: targetGroup)

        case .epic:
            // targetGroup is either "No Epic" or "EPIC-KEY: Epic Summary"
            await bulkUpdateEpic(issueKeys: issueKeys, epicGroup: targetGroup)

        case .initiative:
            // targetGroup is the project name (initiative placeholder)
            await bulkUpdateInitiative(issueKeys: issueKeys, initiative: targetGroup)
        }
    }

    private func bulkUpdateAssignee(issueKeys: [String], assignee: String) async {
        let assigneeEmail: String?

        if assignee == "Unassigned" {
            assigneeEmail = nil
        } else {
            // Try to find the email from loaded issues
            assigneeEmail = jiraService.issues.first { $0.assignee == assignee }?.fields.assignee?.emailAddress
        }

        for issueKey in issueKeys {
            if let email = assigneeEmail {
                _ = await jiraService.assignIssue(issueKey: issueKey, assigneeEmail: email)
            }
        }
    }

    private func bulkUpdateStatus(issueKeys: [String], status: String) async {
        for issueKey in issueKeys {
            _ = await jiraService.updateIssueStatus(issueKey: issueKey, newStatus: status)
        }
    }

    private func bulkUpdateEpic(issueKeys: [String], epicGroup: String) async {
        var epicKey: String?

        if epicGroup == "No Epic" {
            epicKey = nil
        } else {
            // Extract epic key from "EPIC-KEY: Epic Summary" format
            if let colonIndex = epicGroup.firstIndex(of: ":") {
                epicKey = String(epicGroup[..<colonIndex])
            } else {
                epicKey = epicGroup
            }
        }

        for issueKey in issueKeys {
            if let epic = epicKey {
                _ = await jiraService.updateIssue(issueKey: issueKey, fields: ["epic": epic])
            } else {
                _ = await jiraService.updateIssue(issueKey: issueKey, fields: ["customfield_10014": NSNull()])
            }
        }
    }

    private func bulkUpdateInitiative(issueKeys: [String], initiative: String) async {
        // Initiative is mapped to project - this would require moving issues between projects
        // which is a complex operation in Jira. For now, we'll log a warning.
        Logger.shared.warning("Bulk initiative (project) changes not yet supported")
    }
}

struct IssueRow: View {
    let issue: JiraIssue
    @Environment(\.textSizeMultiplier) var textSizeMultiplier
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var jiraService: JiraService
    @State private var showingLogWork = false

    private func scaledFont(_ textStyle: Font.TextStyle) -> Font {
        let baseSize: CGFloat = {
            switch textStyle {
            case .body: return 13
            case .caption: return 10
            default: return 13
            }
        }()
        return .system(size: baseSize * textSizeMultiplier)
    }

    private var issueURL: URL? {
        let urlString = "\(Configuration.shared.jiraBaseURL)/browse/\(issue.key)"
        return URL(string: urlString)
    }

    private func openInBrowser() {
        guard let url = issueURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyLink() {
        guard let url = issueURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func openDetailWindow() {
        openWindow(value: issue.key)
    }

    private func openAllSelectedDetailWindows() {
        // Get all selected issues
        let selectedIssues = jiraService.selectedIssues.compactMap { selectedID in
            jiraService.issues.first { $0.id == selectedID }
        }

        // Open a detail window for each
        for issue in selectedIssues {
            openWindow(value: issue.key)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Issue key
                Text(issue.key)
                    .font(.system(size: 13 * textSizeMultiplier, design: .monospaced))
                    .foregroundColor(.blue)

                // Issue type badge
                Text(issue.issueType)
                    .font(scaledFont(.caption))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                // Status dropdown
                StatusDropdown(issue: issue)

                // Priority if available
                if let priority = issue.priority {
                    Text(priority)
                        .font(scaledFont(.caption))
                        .foregroundColor(.secondary)
                }

                // Log work button
                Button(action: { showingLogWork = true }) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14 * textSizeMultiplier))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Log work (⌘L)")
            }

            // Summary
            Text(issue.summary)
                .font(scaledFont(.body))
                .lineLimit(2)

            // Metadata
            HStack(spacing: 12) {
                Label(issue.project, systemImage: "folder")
                    .font(scaledFont(.caption))
                    .foregroundColor(.secondary)

                // Sprint or Backlog
                if let sprints = issue.fields.customfield_10020, !sprints.isEmpty, let firstSprint = sprints.first {
                    Label(firstSprint.name, systemImage: "arrow.triangle.2.circlepath")
                        .font(scaledFont(.caption))
                        .foregroundColor(.orange)
                } else {
                    Label("Backlog", systemImage: "tray")
                        .font(scaledFont(.caption))
                        .foregroundColor(.gray)
                }

                if let assignee = issue.assignee {
                    Label(assignee, systemImage: "person")
                        .font(scaledFont(.caption))
                        .foregroundColor(.secondary)
                }

                if let epic = issue.epic {
                    Label(epic, systemImage: "flag")
                        .font(scaledFont(.caption))
                        .foregroundColor(.purple)
                }

                // Time tracking fields
                if let originalEstimate = issue.fields.timeoriginalestimate {
                    Label(formatTime(seconds: originalEstimate), systemImage: "clock")
                        .font(scaledFont(.caption))
                        .foregroundColor(.secondary)
                }

                if let timeSpent = issue.fields.timespent {
                    Label(formatTime(seconds: timeSpent), systemImage: "timer")
                        .font(scaledFont(.caption))
                        .foregroundColor(.blue)
                }

                if let timeRemaining = issue.fields.timeestimate {
                    Label(formatTime(seconds: timeRemaining), systemImage: "hourglass")
                        .font(scaledFont(.caption))
                        .foregroundColor(.orange)
                }

                Spacer()

                if let updated = issue.updated {
                    Text(timeAgo(from: updated))
                        .font(scaledFont(.caption))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onTapGesture(count: 2) {
            openDetailWindow()
        }
        .contextMenu {
            // Show "Open All" if multiple issues selected
            if jiraService.selectedIssues.count > 1 {
                Button(action: openAllSelectedDetailWindows) {
                    Label("Open All (\(jiraService.selectedIssues.count))", systemImage: "doc.on.doc")
                }

                Divider()
            }

            Button(action: openInBrowser) {
                Label("Open in Jira", systemImage: "safari")
            }

            Button(action: copyLink) {
                Label("Copy Link", systemImage: "link")
            }

            Button(action: { showingLogWork = true }) {
                Label("Log Work", systemImage: "clock.fill")
            }
        }
        .sheet(isPresented: $showingLogWork) {
            LogWorkView(issue: issue, isPresented: $showingLogWork)
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours == 0 && minutes == 0 {
            return "\(seconds)s"
        } else if hours == 0 {
            return "\(minutes)m"
        } else if minutes == 0 {
            return "\(hours)h"
        } else if hours >= 8 {
            let days = hours / 8
            let remainingHours = hours % 8
            if remainingHours == 0 {
                return "\(days)d"
            }
            return "\(days)d \(remainingHours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
}

struct StatusDropdown: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.textSizeMultiplier) var textSizeMultiplier

    @State private var showingTransitionFields = false
    @State private var pendingTransitionInfo: TransitionInfo?
    @State private var pendingTargetStatus: String = ""

    private func backgroundColor(for status: String) -> Color {
        switch status.lowercased() {
        case let s where s.contains("done") || s.contains("closed"):
            return .green
        case let s where s.contains("progress"):
            return .blue
        case let s where s.contains("review"):
            return .orange
        default:
            return .gray
        }
    }

    var body: some View {
        Menu {
            ForEach(jiraService.availableStatuses.sorted(), id: \.self) { status in
                Button(action: {
                    Task {
                        await handleStatusChange(to: status)
                    }
                }) {
                    HStack {
                        Text(status)
                        if issue.status == status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(issue.status)
                .font(.system(size: 10 * textSizeMultiplier))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(backgroundColor(for: issue.status).opacity(0.2))
                .foregroundColor(backgroundColor(for: issue.status).darker())
                .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showingTransitionFields) {
            if let transitionInfo = pendingTransitionInfo {
                TransitionFieldsView(
                    issue: issue,
                    targetStatus: pendingTargetStatus,
                    transitionInfo: transitionInfo,
                    isPresented: $showingTransitionFields
                )
            }
        }
    }

    private func handleStatusChange(to newStatus: String) async {
        // Check if this transition requires additional fields
        if let transitionInfo = await jiraService.getTransitionInfo(issueKey: issue.key, targetStatus: newStatus) {
            if transitionInfo.requiredFields.isEmpty {
                // No required fields, transition directly
                let _ = await jiraService.updateIssueStatus(issueKey: issue.key, newStatus: newStatus)
            } else {
                // Has required fields, show the dialog
                await MainActor.run {
                    pendingTransitionInfo = transitionInfo
                    pendingTargetStatus = newStatus
                    showingTransitionFields = true
                }
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    @Environment(\.textSizeMultiplier) var textSizeMultiplier

    var backgroundColor: Color {
        switch status.lowercased() {
        case let s where s.contains("done") || s.contains("closed"):
            return .green
        case let s where s.contains("progress"):
            return .blue
        case let s where s.contains("review"):
            return .orange
        default:
            return .gray
        }
    }

    var body: some View {
        Text(status)
            .font(.system(size: 10 * textSizeMultiplier))
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor.opacity(0.2))
            .foregroundColor(backgroundColor.darker())
            .cornerRadius(6)
    }
}

// MARK: - Transition Fields View

struct TransitionFieldsView: View {
    let issue: JiraIssue
    let targetStatus: String
    let transitionInfo: TransitionInfo
    @Binding var isPresented: Bool
    @EnvironmentObject var jiraService: JiraService

    @State private var fieldValues: [String: String] = [:]
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transition to \(targetStatus)")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(issue.key): \(issue.summary)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                Text("Required Fields")
                    .font(.headline)

                ForEach(transitionInfo.requiredFields, id: \.key) { field in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if field.allowedValues.isEmpty {
                            TextField("Enter \(field.name.lowercased())", text: Binding(
                                get: { fieldValues[field.key] ?? "" },
                                set: { fieldValues[field.key] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: Binding(
                                get: { fieldValues[field.key] ?? field.allowedValues.first ?? "" },
                                set: { fieldValues[field.key] = $0 }
                            )) {
                                ForEach(field.allowedValues, id: \.self) { value in
                                    Text(value).tag(value)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Update Status") {
                    updateStatus()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isUpdating || !allRequiredFieldsFilled)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 450, height: CGFloat(250 + transitionInfo.requiredFields.count * 70))
        .onAppear {
            // Initialize field values with first allowed value for pickers
            for field in transitionInfo.requiredFields {
                if !field.allowedValues.isEmpty {
                    fieldValues[field.key] = field.allowedValues.first
                }
            }
        }
    }

    private var allRequiredFieldsFilled: Bool {
        for field in transitionInfo.requiredFields {
            if let value = fieldValues[field.key], !value.isEmpty {
                continue
            } else {
                return false
            }
        }
        return true
    }

    private func updateStatus() {
        isUpdating = true
        errorMessage = nil

        Task {
            let success = await jiraService.updateIssueStatus(
                issueKey: issue.key,
                newStatus: targetStatus,
                fieldValues: fieldValues
            )

            await MainActor.run {
                isUpdating = false
                if success {
                    isPresented = false
                } else {
                    errorMessage = "Failed to update status. Please try again."
                }
            }
        }
    }
}

// MARK: - Log Work View

struct LogWorkView: View {
    let issue: JiraIssue
    @Binding var isPresented: Bool
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails

    @State private var timeInput: String = ""
    @State private var errorMessage: String?
    @State private var isLogging = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Log Work")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(issue.key): \(issue.summary)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Time Spent")
                    .font(.headline)

                TextField("e.g., 30m, 2h, 1d", text: $timeInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)

                Text("Format: 30m (minutes), 2h (hours), 1d (days)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Log Work") {
                    logWork()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(timeInput.isEmpty || isLogging)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 280)
    }

    private func logWork() {
        guard let seconds = parseTimeString(timeInput) else {
            errorMessage = "Invalid time format. Use formats like 30m, 2h, or 1d"
            return
        }

        isLogging = true
        errorMessage = nil

        Task {
            let success = await jiraService.logWork(issueKey: issue.key, timeSpentSeconds: seconds)
            await MainActor.run {
                isLogging = false
                if success {
                    refreshIssueDetails()
                    isPresented = false
                } else {
                    errorMessage = "Failed to log work. Please try again."
                }
            }
        }
    }

    private func parseTimeString(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // Extract number and unit
        guard let lastChar = trimmed.last else { return nil }

        let numberPart = trimmed.dropLast()
        guard let value = Int(numberPart) else { return nil }

        switch lastChar {
        case "m":
            return value * 60 // minutes to seconds
        case "h":
            return value * 3600 // hours to seconds
        case "d":
            return value * 8 * 3600 // days to seconds (8-hour workday)
        default:
            return nil
        }
    }
}

// MARK: - Color Extension

extension Color {
    func darker() -> Color {
        // Convert to RGB color space first to avoid crashes with catalog/dynamic colors
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return self // Return original if conversion fails
        }

        return Color(
            red: Double(nsColor.redComponent * 0.8),
            green: Double(nsColor.greenComponent * 0.8),
            blue: Double(nsColor.blueComponent * 0.8)
        )
    }
}

// MARK: - Issue List Toolbar

struct IssueListToolbar: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFocused: Bool
    let sortOption: SortOption
    let sortDirection: SortDirection
    let groupOption: GroupOption
    let groupedIssues: [(String, [JiraIssue])]
    let totalIssueCount: Int
    @Binding var expandedSections: Set<String>
    let onSortOptionChange: (SortOption) -> Void
    let onSortDirectionChange: (SortDirection) -> Void
    let onGroupOptionChange: (GroupOption) -> Void
    let clientCreatedFilter: CreatedFilter
    let onCreatedFilterChange: (CreatedFilter) -> Void
    let clientTypeFilter: String
    let onTypeFilterChange: (String) -> Void
    let clientStatusFilter: String
    let onStatusFilterChange: (String) -> Void
    @EnvironmentObject var jiraService: JiraService

    private var availableTypes: [String] {
        let types = Set(jiraService.issues.map { $0.issueType }).sorted()
        return ["all"] + types
    }

    private var availableStatuses: [String] {
        let statuses = Set(jiraService.issues.map { $0.status }).sorted()
        return ["all"] + statuses
    }

    var body: some View {
        HStack(spacing: 12) {
            // Expand/Collapse all buttons (only show when grouping is active)
            if groupedIssues.count > 1 {
                HStack(spacing: 8) {
                    Button("Expand all") {
                        expandedSections = Set(groupedIssues.map { $0.0 })
                    }
                    .buttonStyle(.plain)

                    Button("Collapse all") {
                        expandedSections.removeAll()
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 20)
            }

            // Group menu
            Menu {
                ForEach(GroupOption.allCases) { option in
                    Button(action: { onGroupOptionChange(option) }) {
                        HStack {
                            Text(option.rawValue)
                            if groupOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Group", systemImage: "folder.badge.gearshape")
            }
            .help("Group issues")
            .fixedSize()

            // Sort menu
            Menu {
                Section("Sort By") {
                    ForEach(SortOption.allCases) { option in
                        Button(action: { onSortOptionChange(option) }) {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Section("Direction") {
                    Button(action: { onSortDirectionChange(.ascending) }) {
                        HStack {
                            Text("Ascending")
                            if sortDirection == .ascending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button(action: { onSortDirectionChange(.descending) }) {
                        HStack {
                            Text("Descending")
                            if sortDirection == .descending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort issues")
            .fixedSize()

            Divider()
                .frame(height: 20)

            // Client-side filters
            // Created date filter
            Menu {
                ForEach(CreatedFilter.allCases) { filter in
                    Button(action: { onCreatedFilterChange(filter) }) {
                        HStack {
                            Text(filter.rawValue)
                            if clientCreatedFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(clientCreatedFilter == .all ? "Created" : clientCreatedFilter.rawValue, systemImage: "calendar")
            }
            .help("Filter by creation date")
            .fixedSize()

            // Type filter
            Menu {
                ForEach(availableTypes, id: \.self) { type in
                    Button(action: { onTypeFilterChange(type) }) {
                        HStack {
                            Text(type == "all" ? "All" : type)
                            if clientTypeFilter == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(clientTypeFilter == "all" ? "Type" : clientTypeFilter, systemImage: "doc.text")
            }
            .help("Filter by issue type")
            .fixedSize()

            // Status filter
            Menu {
                ForEach(availableStatuses, id: \.self) { status in
                    Button(action: { onStatusFilterChange(status) }) {
                        HStack {
                            Text(status == "all" ? "All" : status)
                            if clientStatusFilter == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(clientStatusFilter == "all" ? "Status" : clientStatusFilter, systemImage: "checkmark.circle")
            }
            .help("Filter by status")
            .fixedSize()

            Spacer()

            // Issue count and load more
            HStack(spacing: 8) {
                Text("\(totalIssueCount) of \(jiraService.totalIssuesAvailable) \(jiraService.totalIssuesAvailable == 1 ? "issue" : "issues")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if jiraService.hasMoreIssues {
                    Button("Get more...") {
                        Task {
                            await jiraService.loadMoreIssues()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search issues...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .onAppear {
            // Register keyboard shortcut for search
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                    isSearchFocused = true
                    return nil
                }
                return event
            }
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @EnvironmentObject var jiraService: JiraService

    var body: some View {
        HStack(spacing: 12) {
            if jiraService.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("Loading issues...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Show current filter status
            if !jiraService.filters.projects.isEmpty ||
               !jiraService.filters.statuses.isEmpty ||
               !jiraService.filters.assignees.isEmpty ||
               !jiraService.filters.issueTypes.isEmpty ||
               !jiraService.filters.epics.isEmpty ||
               !jiraService.filters.sprints.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Filters active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

// MARK: - Client-Side Filters

enum CreatedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case last24Hours = "Last 24 hours"
    case lastWeek = "Last week"
    case lastMonth = "Last month"
    case lastSixMonths = "Last 6 months"

    var id: String { rawValue }

    var cutoffDate: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .all:
            return Date.distantPast
        case .last24Hours:
            return calendar.date(byAdding: .hour, value: -24, to: now) ?? now
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .lastSixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now) ?? now
        }
    }
}

// MARK: - Text Size Environment

private struct TextSizeMultiplierKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

// MARK: - Quick Create Issue View

struct QuickCreateIssueView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var jiraService: JiraService

    @AppStorage("defaultAssignee") private var defaultAssignee: String = ""
    @AppStorage("defaultProject") private var defaultProject: String = ""
    @AppStorage("defaultComponent") private var defaultComponent: String = ""
    @AppStorage("defaultEpic") private var defaultEpic: String = ""

    @State private var summary: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isSummaryFocused: Bool

    private var canCreate: Bool {
        !summary.isEmpty && !defaultProject.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Enter issue summary...", text: $summary)
                .textFieldStyle(.roundedBorder)
                .focused($isSummaryFocused)
                .onSubmit {
                    if canCreate {
                        createIssue()
                    }
                }
                .frame(width: 350)

            if !defaultProject.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(defaultProject)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("No default project set")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(12)
        .onAppear {
            isSummaryFocused = true
        }
    }

    private func createIssue() {
        guard canCreate else { return }

        isCreating = true
        errorMessage = nil

        Task {
            var fields: [String: Any] = [
                "project": defaultProject,
                "summary": summary,
                "type": "Story" // Default to Story
            ]

            if !defaultAssignee.isEmpty {
                fields["assignee"] = defaultAssignee
            }

            if !defaultComponent.isEmpty {
                fields["components"] = [defaultComponent]
            }

            if !defaultEpic.isEmpty {
                fields["epic"] = defaultEpic
            }

            let (success, issueKey) = await jiraService.createIssue(fields: fields)

            await MainActor.run {
                isCreating = false

                if success {
                    Logger.shared.info("Created issue: \(issueKey ?? "unknown")")
                    // Refresh issues to show the new one
                    Task {
                        await jiraService.fetchMyIssues(updateAvailableOptions: false)
                    }
                    isPresented = false
                } else {
                    errorMessage = "Failed to create issue. Check logs for details."
                }
            }
        }
    }
}

extension EnvironmentValues {
    var textSizeMultiplier: Double {
        get { self[TextSizeMultiplierKey.self] }
        set { self[TextSizeMultiplierKey.self] = newValue }
    }
}
