import SwiftUI

/// A reusable user selector component with autocomplete functionality
/// Can be used for both assignee and reporter fields
struct UserSelector: View {
    let issue: JiraIssue
    let fieldType: UserFieldType
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails

    @State private var showingPopover = false
    @State private var searchText = ""
    @State private var searchResults: [(displayName: String, accountId: String, email: String)] = []
    @State private var isSearching = false
    @State private var selectedIndex = 0
    @State private var isUpdating = false

    enum UserFieldType {
        case assignee
        case reporter

        var label: String {
            switch self {
            case .assignee: return "Assignee"
            case .reporter: return "Reporter"
            }
        }

        var icon: String {
            switch self {
            case .assignee: return "person"
            case .reporter: return "person.badge.plus"
            }
        }

        var fieldKey: String {
            switch self {
            case .assignee: return "assignee"
            case .reporter: return "reporter"
            }
        }
    }

    private var currentValue: String {
        switch fieldType {
        case .assignee:
            return issue.assignee ?? "Unassigned"
        case .reporter:
            return issue.reporter ?? "Unknown"
        }
    }

    private var isUnset: Bool {
        switch fieldType {
        case .assignee:
            return issue.assignee == nil
        case .reporter:
            return issue.reporter == nil
        }
    }

    var body: some View {
        Button(action: { showingPopover = true }) {
            HStack(spacing: 4) {
                Image(systemName: fieldType.icon)
                    .font(.system(size: 10))
                Text(currentValue)
                    .font(.system(size: 11))
                    .lineLimit(1)
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                }
            }
            .foregroundColor(isUnset ? .secondary : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Click to change \(fieldType.label.lowercased())")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            userSearchPopover
        }
    }

    private var userSearchPopover: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search users...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if !searchResults.isEmpty && selectedIndex < searchResults.count {
                            selectUser(searchResults[selectedIndex])
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Results list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Unassign option (only for assignee)
                    if fieldType == .assignee {
                        Button(action: {
                            unassignUser()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.slash")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                Text("Unassigned")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isUnset ? Color.accentColor.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }

                    if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                        Text("No users found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else if searchResults.isEmpty && searchText.isEmpty {
                        Text("Type to search users")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(searchResults.enumerated()), id: \.element.accountId) { index, user in
                            Button(action: {
                                selectUser(user)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.primary)
                                        if !user.email.isEmpty {
                                            Text(user.email)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if currentValue == user.displayName {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(index == selectedIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < searchResults.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(width: 280, height: 200)
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
        .onAppear {
            // Load initial results when popover opens
            performSearch(query: "")
        }
    }

    private func performSearch(query: String) {
        isSearching = true
        selectedIndex = 0

        Task {
            let users = await jiraService.searchUsers(query: query)
            await MainActor.run {
                searchResults = users
                isSearching = false
            }
        }
    }

    private func selectUser(_ user: (displayName: String, accountId: String, email: String)) {
        showingPopover = false
        isUpdating = true

        Task {
            // Use accountId directly to avoid ambiguity with duplicate display names
            let urlString = "\(jiraService.config.jiraBaseURL)/rest/api/3/issue/\(issue.key)"
            guard let url = URL(string: urlString) else {
                await MainActor.run { isUpdating = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            let credentials = "\(jiraService.config.jiraEmail):\(jiraService.config.jiraAPIKey)"
            let credentialData = credentials.data(using: .utf8)!
            let base64Credentials = credentialData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = ["fields": [fieldType.fieldKey: ["accountId": user.accountId]]]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                let success = httpResponse?.statusCode == 204 || httpResponse?.statusCode == 200

                await MainActor.run {
                    isUpdating = false
                    if success {
                        Logger.shared.info("Updated \(fieldType.label) for \(issue.key) to \(user.displayName) (accountId: \(user.accountId))")
                        Task {
                            await jiraService.fetchMyIssues()
                        }
                        refreshIssueDetails()
                    } else {
                        if let errorMessage = String(data: data, encoding: .utf8) {
                            Logger.shared.error("Failed to update \(fieldType.label) for \(issue.key): \(errorMessage)")
                        }
                    }
                }
            } catch {
                await MainActor.run { isUpdating = false }
                Logger.shared.error("Failed to update \(fieldType.label): \(error)")
            }
        }
    }

    private func unassignUser() {
        showingPopover = false
        isUpdating = true

        Task {
            // For unassigning, we need to send null
            let urlString = "\(jiraService.config.jiraBaseURL)/rest/api/3/issue/\(issue.key)"
            guard let url = URL(string: urlString) else {
                await MainActor.run { isUpdating = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            let credentials = "\(jiraService.config.jiraEmail):\(jiraService.config.jiraAPIKey)"
            let credentialData = credentials.data(using: .utf8)!
            let base64Credentials = credentialData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = ["fields": ["assignee": NSNull()]]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let success = (response as? HTTPURLResponse)?.statusCode == 204

                await MainActor.run {
                    isUpdating = false
                    if success {
                        Logger.shared.info("Unassigned \(issue.key)")
                        Task {
                            await jiraService.fetchMyIssues()
                        }
                        refreshIssueDetails()
                    }
                }
            } catch {
                await MainActor.run { isUpdating = false }
                Logger.shared.error("Failed to unassign: \(error)")
            }
        }
    }
}

/// Compact version for use in list rows
struct CompactUserSelector: View {
    let issue: JiraIssue
    let fieldType: UserSelector.UserFieldType
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.textSizeMultiplier) var textSizeMultiplier

    @State private var showingPopover = false
    @State private var searchText = ""
    @State private var searchResults: [(displayName: String, accountId: String, email: String)] = []
    @State private var isSearching = false
    @State private var isUpdating = false

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

    private var currentValue: String? {
        switch fieldType {
        case .assignee:
            return issue.assignee
        case .reporter:
            return issue.reporter
        }
    }

    var body: some View {
        if let value = currentValue {
            Button(action: { showingPopover = true }) {
                HStack(spacing: 2) {
                    Label(value, systemImage: fieldType.icon)
                        .font(scaledFont(.caption))
                        .foregroundColor(.secondary)
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Click to change \(fieldType.label.lowercased())")
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                userSearchPopover
            }
        }
    }

    private var userSearchPopover: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search users...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Results list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Unassign option (only for assignee)
                    if fieldType == .assignee {
                        Button(action: {
                            unassignUser()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.slash")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                Text("Unassigned")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }

                    if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                        Text("No users found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else if searchResults.isEmpty && searchText.isEmpty {
                        Text("Type to search users")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(searchResults.enumerated()), id: \.element.accountId) { index, user in
                            Button(action: {
                                selectUser(user)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.primary)
                                        if !user.email.isEmpty {
                                            Text(user.email)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if currentValue == user.displayName {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < searchResults.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(width: 280, height: 200)
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
        .onAppear {
            performSearch(query: "")
        }
    }

    private func performSearch(query: String) {
        isSearching = true

        Task {
            let users = await jiraService.searchUsers(query: query)
            await MainActor.run {
                searchResults = users
                isSearching = false
            }
        }
    }

    private func selectUser(_ user: (displayName: String, accountId: String, email: String)) {
        showingPopover = false
        isUpdating = true

        Task {
            // Use accountId directly to avoid ambiguity with duplicate display names
            let urlString = "\(jiraService.config.jiraBaseURL)/rest/api/3/issue/\(issue.key)"
            guard let url = URL(string: urlString) else {
                await MainActor.run { isUpdating = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            let credentials = "\(jiraService.config.jiraEmail):\(jiraService.config.jiraAPIKey)"
            let credentialData = credentials.data(using: .utf8)!
            let base64Credentials = credentialData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = ["fields": [fieldType.fieldKey: ["accountId": user.accountId]]]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                let success = httpResponse?.statusCode == 204 || httpResponse?.statusCode == 200

                await MainActor.run {
                    isUpdating = false
                    if success {
                        Logger.shared.info("Updated \(fieldType.label) for \(issue.key) to \(user.displayName) (accountId: \(user.accountId))")
                        Task {
                            await jiraService.fetchMyIssues()
                        }
                    } else {
                        if let errorMessage = String(data: data, encoding: .utf8) {
                            Logger.shared.error("Failed to update \(fieldType.label) for \(issue.key): \(errorMessage)")
                        }
                    }
                }
            } catch {
                await MainActor.run { isUpdating = false }
                Logger.shared.error("Failed to update \(fieldType.label): \(error)")
            }
        }
    }

    private func unassignUser() {
        showingPopover = false
        isUpdating = true

        Task {
            let urlString = "\(jiraService.config.jiraBaseURL)/rest/api/3/issue/\(issue.key)"
            guard let url = URL(string: urlString) else {
                await MainActor.run { isUpdating = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            let credentials = "\(jiraService.config.jiraEmail):\(jiraService.config.jiraAPIKey)"
            let credentialData = credentials.data(using: .utf8)!
            let base64Credentials = credentialData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = ["fields": ["assignee": NSNull()]]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let success = (response as? HTTPURLResponse)?.statusCode == 204

                await MainActor.run {
                    isUpdating = false
                    if success {
                        Logger.shared.info("Unassigned \(issue.key)")
                        Task {
                            await jiraService.fetchMyIssues()
                        }
                    }
                }
            } catch {
                await MainActor.run { isUpdating = false }
                Logger.shared.error("Failed to unassign: \(error)")
            }
        }
    }
}
