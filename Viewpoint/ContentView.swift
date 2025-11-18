import SwiftUI

struct ContentView: View {
    @EnvironmentObject var jiraService: JiraService
    @State private var selectedIssue: JiraIssue?
    @AppStorage("showFilters") private var showFilters: Bool = true
    @AppStorage("sortOption") private var sortOptionRaw: String = "dateCreated"
    @AppStorage("sortDirection") private var sortDirectionRaw: String = "descending"
    @AppStorage("groupOption") private var groupOptionRaw: String = "none"
    @AppStorage("textSize") private var textSize: Double = 1.0
    @AppStorage("filterPanelHeight") private var filterPanelHeight: Double = 0
    @State private var showingLogWorkForSelected = false
    @AppStorage("colorScheme") private var colorSchemePreference: String = "auto"
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

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

    var filteredIssues: [JiraIssue] {
        if searchText.isEmpty {
            return jiraService.issues
        }

        let lowercasedSearch = searchText.lowercased()
        return jiraService.issues.filter { issue in
            issue.key.lowercased().contains(lowercasedSearch) ||
            issue.summary.lowercased().contains(lowercasedSearch)
        }
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

        return grouped.sorted { $0.key < $1.key }
    }

    private func filterHeight(totalHeight: CGFloat) -> CGFloat {
        // Subtract header height (approximately 80px)
        let availableHeight = totalHeight - 80

        // Filter panel gets 20% of available space (issue list gets 80%)
        return availableHeight * 0.2
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with title and refresh
                HeaderView(filteredCount: filteredIssues.count, searchText: searchText)

                // Filter panel (fixed 30% height)
                if showFilters {
                    FilterPanel()
                        .frame(height: filterHeight(totalHeight: geometry.size.height))
                }

                // Issue list (takes remaining space)
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
                        IssueListView(selectedIssue: $selectedIssue, groupedIssues: groupedIssues)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingLogWorkForSelected) {
            if let issue = selectedIssue {
                LogWorkView(issue: issue, isPresented: $showingLogWorkForSelected)
            }
        }
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "toggleFilters", placement: .navigation, showsByDefault: true) {
                Button(action: { showFilters.toggle() }) {
                    Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                }
            }

            ToolbarItem(id: "logWork", placement: .automatic, showsByDefault: true) {
                // Log work for selected issue
                Button(action: {
                    if selectedIssue != nil {
                        showingLogWorkForSelected = true
                    }
                }) {
                    Image(systemName: "clock.fill")
                }
                .keyboardShortcut("l", modifiers: .command)
                .help("Log work for selected issue (⌘L)")
                .disabled(selectedIssue == nil)
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

                    // Grouping menu
                    Menu {
                        ForEach(GroupOption.allCases) { option in
                            Button(action: { groupOptionRaw = option.rawValue }) {
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

                    Divider()

                    // Sorting menu
                    Menu {
                        Section("Sort By") {
                            ForEach(SortOption.allCases) { option in
                                Button(action: { sortOptionRaw = option.rawValue }) {
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
                            Button(action: { sortDirectionRaw = "ascending" }) {
                                HStack {
                                    Text("Ascending")
                                    if sortDirection == .ascending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button(action: { sortDirectionRaw = "descending" }) {
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

                    Divider()

                    // Refresh button
                    Button(action: { jiraService.refresh() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh issues")
                }
            }

            // Search field on the far right
            ToolbarItem(id: "search", placement: .automatic, showsByDefault: true) {
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

            // Hidden keyboard shortcut for search
            ToolbarItem(id: "searchShortcut", placement: .automatic, showsByDefault: false) {
                Button("") {
                    isSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .help("Focus search (⌘F)")
            }

            // Flexible space items for customization
            ToolbarItem(id: "flexibleSpace1", placement: .automatic, showsByDefault: false) {
                Spacer()
            }

            ToolbarItem(id: "flexibleSpace2", placement: .automatic, showsByDefault: false) {
                Spacer()
            }

            // Fixed space items for customization
            ToolbarItem(id: "fixedSpace1", placement: .automatic, showsByDefault: false) {
                Spacer()
                    .frame(width: 20)
            }

            ToolbarItem(id: "fixedSpace2", placement: .automatic, showsByDefault: false) {
                Spacer()
                    .frame(width: 20)
            }

            ToolbarItem(id: "fixedSpace3", placement: .automatic, showsByDefault: false) {
                Spacer()
                    .frame(width: 20)
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
    @Binding var selectedIssue: JiraIssue?
    let groupedIssues: [(String, [JiraIssue])]

    var body: some View {
        List(selection: $selectedIssue) {
            ForEach(groupedIssues, id: \.0) { groupName, issues in
                if groupedIssues.count > 1 {
                    Section(header: Text(groupName).font(.headline)) {
                        ForEach(issues) { issue in
                            IssueRow(issue: issue)
                                .tag(issue)
                        }
                    }
                } else {
                    ForEach(issues) { issue in
                        IssueRow(issue: issue)
                            .tag(issue)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct IssueRow: View {
    let issue: JiraIssue
    @Environment(\.textSizeMultiplier) var textSizeMultiplier
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
            openInBrowser()
        }
        .contextMenu {
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

// MARK: - Text Size Environment

private struct TextSizeMultiplierKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var textSizeMultiplier: Double {
        get { self[TextSizeMultiplierKey.self] }
        set { self[TextSizeMultiplierKey.self] = newValue }
    }
}
