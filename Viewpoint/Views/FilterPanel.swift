import SwiftUI

struct FilterPanel: View {
    @EnvironmentObject var jiraService: JiraService
    @State private var expandedSections: Set<FilterCategory> = [.project]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // JQL Builder
                VStack(alignment: .leading, spacing: 4) {
                    Text("JQL Query")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)

                    JQLBuilderView(jiraService: jiraService)
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)

                Divider()

                // Show only my issues toggle and filter controls
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { jiraService.filters.showOnlyMyIssues },
                            set: { value in
                                jiraService.filters.showOnlyMyIssues = value
                                jiraService.applyFilters()
                            }
                        )) {
                            HStack {
                                Image(systemName: "person.circle")
                                    .foregroundColor(.accentColor)
                                Text("Show only my issues")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    // Filter control buttons
                    HStack(spacing: 8) {
                        // Expand/Collapse all buttons
                        Button("Expand all") {
                            expandedSections = Set(FilterCategory.allCases)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)

                        Button("Collapse all") {
                            expandedSections.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)

                        Divider()
                            .frame(height: 12)

                        // Clear filters button
                        Button("Clear filters") {
                            clearFilters()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Project Filter - PRIMARY FILTER
                FilterSection(
                    title: "Project",
                    icon: "folder",
                    section: .project,
                    isExpanded: expandedSections.contains(.project)
                ) {
                    expandedSections.toggle(.project)
                } content: {
                    MultiSelectFilter(
                        options: Array(jiraService.availableProjects),
                        selectedOptions: Binding(
                            get: { jiraService.filters.projects },
                            set: { newProjects in
                                let oldProjects = jiraService.filters.projects
                                jiraService.filters.projects = newProjects

                                // Clear sprint selections when projects change
                                if oldProjects != newProjects {
                                    jiraService.filters.sprints.removeAll()
                                }
                            }
                        )
                    )
                }

                Divider()

                // Status Filter
                FilterSection(
                    title: "Status",
                    icon: "checkmark.circle",
                    section: .status,
                    isExpanded: expandedSections.contains(.status)
                ) {
                    expandedSections.toggle(.status)
                } content: {
                    MultiSelectFilter(
                        options: Array(jiraService.availableStatuses),
                        selectedOptions: Binding(
                            get: { jiraService.filters.statuses },
                            set: { jiraService.filters.statuses = $0 }
                        )
                    )
                }

                Divider()

                // Sprint Filter
                FilterSection(
                    title: "Sprint",
                    icon: "flag",
                    section: .sprint,
                    isExpanded: expandedSections.contains(.sprint)
                ) {
                    expandedSections.toggle(.sprint)
                } content: {
                    SprintSelector()
                }

                Divider()

                // Assignee Filter
                FilterSection(
                    title: "Assignee",
                    icon: "person",
                    section: .assignee,
                    isExpanded: expandedSections.contains(.assignee)
                ) {
                    expandedSections.toggle(.assignee)
                } content: {
                    MultiSelectFilter(
                        options: Array(jiraService.availableAssignees),
                        selectedOptions: Binding(
                            get: { jiraService.filters.assignees },
                            set: { jiraService.filters.assignees = $0 }
                        )
                    )
                }

                Divider()

                // Issue Type Filter
                FilterSection(
                    title: "Issue Type",
                    icon: "doc.text",
                    section: .issueType,
                    isExpanded: expandedSections.contains(.issueType)
                ) {
                    expandedSections.toggle(.issueType)
                } content: {
                    MultiSelectFilter(
                        options: Array(jiraService.availableIssueTypes),
                        selectedOptions: Binding(
                            get: { jiraService.filters.issueTypes },
                            set: { jiraService.filters.issueTypes = $0 }
                        )
                    )
                }

                Divider()

                // Epic Filter
                FilterSection(
                    title: "Epic",
                    icon: "star",
                    section: .epic,
                    isExpanded: expandedSections.contains(.epic)
                ) {
                    expandedSections.toggle(.epic)
                } content: {
                    EpicSelector()
                }

                Divider()

                // Time Period Filter
                FilterSection(
                    title: "Time Period",
                    icon: "calendar",
                    section: .timePeriod,
                    isExpanded: expandedSections.contains(.timePeriod)
                ) {
                    expandedSections.toggle(.timePeriod)
                } content: {
                    TimePeriodFilter()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func clearFilters() {
        jiraService.filters.projects.removeAll()
        jiraService.filters.statuses.removeAll()
        jiraService.filters.assignees.removeAll()
        jiraService.filters.issueTypes.removeAll()
        jiraService.filters.epics.removeAll()
        jiraService.filters.sprints.removeAll()
        jiraService.filters.startDate = nil
        jiraService.filters.endDate = nil
        jiraService.applyFilters()
    }
}

// MARK: - Filter Section

enum FilterCategory: Hashable, CaseIterable {
    case status, sprint, assignee, issueType, project, epic, timePeriod
}

struct FilterSection<Content: View>: View {
    let title: String
    let icon: String
    let section: FilterCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 20)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Multi-Select Filter

struct MultiSelectFilter: View {
    let options: [String]
    @Binding var selectedOptions: Set<String>
    @EnvironmentObject var jiraService: JiraService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if options.isEmpty {
                Text("No options available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(options.sorted(), id: \.self) { option in
                    Toggle(isOn: Binding(
                        get: { selectedOptions.contains(option) },
                        set: { isSelected in
                            if isSelected {
                                selectedOptions.insert(option)
                            } else {
                                selectedOptions.remove(option)
                            }
                            jiraService.applyFilters()
                        }
                    )) {
                        Text(option)
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

// MARK: - Sprint Selector

struct SprintSelector: View {
    @EnvironmentObject var jiraService: JiraService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if jiraService.filteredSprints.isEmpty {
                Text("No sprints in current issues")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(jiraService.filteredSprints) { sprint in
                    Toggle(isOn: Binding(
                        get: { jiraService.filters.sprints.contains(sprint.id) },
                        set: { isSelected in
                            if isSelected {
                                jiraService.filters.sprints.insert(sprint.id)
                            } else {
                                jiraService.filters.sprints.remove(sprint.id)
                            }
                            jiraService.applyFilters()
                        }
                    )) {
                        HStack {
                            Text(sprint.name)
                                .font(.caption)

                            Spacer()

                            Text(sprint.state)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(sprintStateColor(sprint.state).opacity(0.2))
                                .cornerRadius(3)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func sprintStateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "active": return .green
        case "future": return .blue
        case "closed": return .gray
        default: return .gray
        }
    }
}

// MARK: - Epic Selector

struct EpicSelector: View {
    @EnvironmentObject var jiraService: JiraService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if jiraService.availableEpics.isEmpty {
                Text("No epics available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(jiraService.availableEpics).sorted(), id: \.self) { epicKey in
                    Toggle(isOn: Binding(
                        get: { jiraService.filters.epics.contains(epicKey) },
                        set: { isSelected in
                            if isSelected {
                                jiraService.filters.epics.insert(epicKey)
                            } else {
                                jiraService.filters.epics.remove(epicKey)
                            }
                            jiraService.applyFilters()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            if let summary = jiraService.epicSummaries[epicKey] {
                                Text(summary)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(epicKey)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(epicKey)
                                    .font(.caption)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

// MARK: - Time Period Filter

struct TimePeriodFilter: View {
    @EnvironmentObject var jiraService: JiraService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                "Start Date",
                selection: Binding(
                    get: { jiraService.filters.startDate ?? Date() },
                    set: { jiraService.filters.startDate = $0 }
                ),
                displayedComponents: .date
            )
            .font(.caption)
            .onChange(of: jiraService.filters.startDate) { _ in
                jiraService.applyFilters()
            }

            DatePicker(
                "End Date",
                selection: Binding(
                    get: { jiraService.filters.endDate ?? Date() },
                    set: { jiraService.filters.endDate = $0 }
                ),
                displayedComponents: .date
            )
            .font(.caption)
            .onChange(of: jiraService.filters.endDate) { _ in
                jiraService.applyFilters()
            }

            Button("Clear Dates") {
                jiraService.filters.startDate = nil
                jiraService.filters.endDate = nil
                jiraService.applyFilters()
            }
            .font(.caption)
        }
    }
}

// MARK: - Set Extension

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}
