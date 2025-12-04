import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            AISettingsTab()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            DefaultsSettingsTab()
                .tabItem {
                    Label("Defaults", systemImage: "slider.horizontal.3")
                }

            PerformanceSettingsTab()
                .tabItem {
                    Label("Performance", systemImage: "gauge")
                }

            LogsSettingsTab()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
        }
        .padding(20)
        .frame(width: 600, height: 550)
    }
}

// MARK: - Connection Settings Tab

struct ConnectionSettingsTab: View {
    @AppStorage("jiraBaseURL") private var jiraBaseURL: String = ""
    @AppStorage("jiraEmail") private var jiraEmail: String = ""
    @State private var jiraAPIKey: String = ""
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Jira Connection Settings")
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Base URL")
                        .font(.subheadline)
                    TextField("https://your-company.atlassian.net", text: $jiraBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                    TextField("your-email@company.com", text: $jiraEmail)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                    SecureField("Enter your API key", text: $jiraAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Create API key", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        .font(.caption)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if showingSuccess {
                Text("Settings saved successfully!")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            loadAPIKey()
        }
    }

    private func saveSettings() {
        errorMessage = nil
        showingSuccess = false

        // Validate inputs
        guard !jiraBaseURL.isEmpty else {
            errorMessage = "Base URL is required"
            return
        }

        guard !jiraEmail.isEmpty else {
            errorMessage = "Email is required"
            return
        }

        guard !jiraAPIKey.isEmpty else {
            errorMessage = "API Key is required"
            return
        }

        // Save API key to Keychain
        if KeychainHelper.save(key: "jiraAPIKey", data: jiraAPIKey) {
            showingSuccess = true

            // Hide success message after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingSuccess = false
            }
        } else {
            errorMessage = "Failed to save API key to Keychain"
        }
    }

    private func loadAPIKey() {
        if let apiKey = KeychainHelper.load(key: "jiraAPIKey") {
            jiraAPIKey = apiKey
        }
    }
}

// MARK: - AI Settings Tab

struct AISettingsTab: View {
    @State private var selectedModel: AIModel = .gemini3ProPreview
    @State private var configurations: [AIModel: VertexConfig] = [:]
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    private let regions = [
        "us-central1", "us-east1", "us-west1", "us-west4",
        "europe-west1", "europe-west4", "asia-southeast1"
    ]

    struct VertexConfig {
        var projectID: String = ""
        var region: String = "us-central1"
        var email: String = ""
    }

    var body: some View {
        Form {
            Section {
                Text("AI Model Selection")
                    .font(.headline)
                    .padding(.bottom, 4)

                Picker("Model", selection: $selectedModel) {
                    ForEach(AIModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section {
                Text("Vertex AI Configuration")
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Project ID")
                        .font(.subheadline)
                    TextField("my-project-123456", text: Binding(
                        get: { configurations[selectedModel]?.projectID ?? "" },
                        set: { newValue in
                            if configurations[selectedModel] == nil {
                                configurations[selectedModel] = VertexConfig()
                            }
                            configurations[selectedModel]?.projectID = newValue
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Region")
                        .font(.subheadline)
                    Picker("", selection: Binding(
                        get: { configurations[selectedModel]?.region ?? "us-central1" },
                        set: { newValue in
                            if configurations[selectedModel] == nil {
                                configurations[selectedModel] = VertexConfig()
                            }
                            configurations[selectedModel]?.region = newValue
                        }
                    )) {
                        ForEach(regions, id: \.self) { region in
                            Text(region).tag(region)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                    TextField("your-email@example.com", text: Binding(
                        get: { configurations[selectedModel]?.email ?? "" },
                        set: { newValue in
                            if configurations[selectedModel] == nil {
                                configurations[selectedModel] = VertexConfig()
                            }
                            configurations[selectedModel]?.email = newValue
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Authentication:")
                        .font(.subheadline)
                        .padding(.top, 8)
                    Text("Run in Terminal:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("gcloud auth application-default login")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if showingSuccess {
                Text("Settings saved successfully!")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            loadConfigurations()
        }
    }

    private func saveSettings() {
        errorMessage = nil
        showingSuccess = false

        guard let config = configurations[selectedModel] else {
            errorMessage = "No configuration found for selected model"
            return
        }

        // Validate inputs
        guard !config.projectID.isEmpty else {
            errorMessage = "Project ID is required"
            return
        }

        guard !config.email.isEmpty else {
            errorMessage = "Email is required"
            return
        }

        // Save configuration for this model
        UserDefaults.standard.set(config.projectID, forKey: "vertexProjectID_\(selectedModel.rawValue)")
        UserDefaults.standard.set(config.region, forKey: "vertexRegion_\(selectedModel.rawValue)")
        UserDefaults.standard.set(config.email, forKey: "vertexEmail_\(selectedModel.rawValue)")

        // Save the selected model as default
        UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedAIModel")

        showingSuccess = true

        // Hide success message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingSuccess = false
        }
    }

    private func loadConfigurations() {
        // Load configurations for all models
        for model in AIModel.allCases {
            let projectID = UserDefaults.standard.string(forKey: "vertexProjectID_\(model.rawValue)") ?? ""
            let region = UserDefaults.standard.string(forKey: "vertexRegion_\(model.rawValue)") ?? "us-central1"
            let email = UserDefaults.standard.string(forKey: "vertexEmail_\(model.rawValue)") ?? ""

            if !projectID.isEmpty || !email.isEmpty {
                configurations[model] = VertexConfig(
                    projectID: projectID,
                    region: region,
                    email: email
                )
            }
        }

        // Load default selected model
        if let savedModel = UserDefaults.standard.string(forKey: "selectedAIModel"),
           let model = AIModel.allCases.first(where: { $0.rawValue == savedModel }) {
            selectedModel = model
        }
    }
}

// MARK: - Defaults Settings Tab

struct DefaultsSettingsTab: View {
    @AppStorage("defaultAssignee") private var defaultAssignee: String = ""
    @AppStorage("defaultProject") private var defaultProject: String = ""
    @AppStorage("defaultComponent") private var defaultComponent: String = ""
    @AppStorage("defaultEpic") private var defaultEpic: String = ""

    @State private var validationStatus: ValidationStatus = .notChecked
    @State private var validationMessage: String = ""
    @State private var isValidating: Bool = false

    enum ValidationStatus {
        case notChecked
        case checking
        case valid
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Issue Defaults")
                .font(.headline)

            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    Text("Assignee")
                        .frame(width: 100, alignment: .trailing)
                    TextField("john@example.com", text: $defaultAssignee)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 20) {
                    Text("Project")
                        .frame(width: 100, alignment: .trailing)
                    TextField("SETI", text: $defaultProject)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 20) {
                    Text("Component")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Management Tasks", text: $defaultComponent)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 20) {
                    Text("Epic")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Epic Name or ID", text: $defaultEpic)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("Set default values for creating new issues. Leave blank for no default.")
                .font(.caption)
                .foregroundColor(.secondary)

            if validationStatus == .checking {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking values...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if validationStatus == .valid {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if validationStatus == .invalid {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            HStack {
                Spacer()
                Button("Check Values") {
                    Task {
                        await validateDefaults()
                    }
                }
                .disabled(isValidating || allFieldsEmpty)
            }
        }
        .padding(20)
    }

    private var allFieldsEmpty: Bool {
        defaultAssignee.isEmpty &&
        defaultProject.isEmpty &&
        defaultComponent.isEmpty &&
        defaultEpic.isEmpty
    }

    private func validateDefaults() async {
        validationStatus = .checking
        isValidating = true
        validationMessage = ""

        var errors: [String] = []

        // Validate each non-empty field
        if !defaultAssignee.isEmpty {
            let valid = await validateAssignee(defaultAssignee)
            if !valid {
                errors.append("Assignee '\(defaultAssignee)' not found")
            }
        }

        if !defaultProject.isEmpty {
            let valid = await validateProject(defaultProject)
            if !valid {
                errors.append("Project '\(defaultProject)' not found")
            }
        }

        if !defaultComponent.isEmpty && !defaultProject.isEmpty {
            let valid = await validateComponent(defaultComponent, inProject: defaultProject)
            if !valid {
                errors.append("Component '\(defaultComponent)' not found in project")
            }
        } else if !defaultComponent.isEmpty && defaultProject.isEmpty {
            errors.append("Component requires a project to be set")
        }

        if !defaultEpic.isEmpty {
            let valid = await validateEpic(defaultEpic)
            if !valid {
                errors.append("Epic '\(defaultEpic)' not found")
            }
        }

        await MainActor.run {
            isValidating = false
            if errors.isEmpty {
                validationStatus = .valid
                validationMessage = "All values are valid!"
            } else {
                validationStatus = .invalid
                validationMessage = errors.joined(separator: "\n")
            }
        }
    }

    private func validateAssignee(_ assignee: String) async -> Bool {
        // Use Jira's user search API
        let config = Configuration.shared
        let encodedQuery = assignee.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? assignee
        let urlString = "\(config.jiraBaseURL)/rest/api/3/user/search?query=\(encodedQuery)"

        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        let credentials = "\(config.jiraEmail):\(config.jiraAPIKey)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            if let users = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return !users.isEmpty
            }
        } catch {
            return false
        }

        return false
    }

    private func validateProject(_ projectKey: String) async -> Bool {
        // Use Jira's project API
        let config = Configuration.shared
        let urlString = "\(config.jiraBaseURL)/rest/api/3/project/\(projectKey)"

        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        let credentials = "\(config.jiraEmail):\(config.jiraAPIKey)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    private func validateComponent(_ componentName: String, inProject projectKey: String) async -> Bool {
        // Use Jira's project components API
        let config = Configuration.shared
        let urlString = "\(config.jiraBaseURL)/rest/api/3/project/\(projectKey)/components"

        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        let credentials = "\(config.jiraEmail):\(config.jiraAPIKey)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            if let components = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return components.contains { component in
                    guard let name = component["name"] as? String else { return false }
                    return name.lowercased() == componentName.lowercased()
                }
            }
        } catch {
            return false
        }

        return false
    }

    private func validateEpic(_ epic: String) async -> Bool {
        // Use Jira's issue search to validate epic
        let config = Configuration.shared
        let jql = "key = \"\(epic)\" OR summary ~ \"\(epic)\""
        let encodedJQL = jql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jql
        let urlString = "\(config.jiraBaseURL)/rest/api/3/search?jql=\(encodedJQL)&maxResults=1"

        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        let credentials = "\(config.jiraEmail):\(config.jiraAPIKey)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let total = json["total"] as? Int {
                return total > 0
            }
        } catch {
            return false
        }

        return false
    }
}

// MARK: - Performance Settings Tab

struct PerformanceSettingsTab: View {
    @AppStorage("initialLoadCount") private var initialLoadCount: Int = 100

    var body: some View {
        Form {
            Section {
                Text("Performance Settings")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Initial Load Count")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        TextField("Count", value: $initialLoadCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)

                        Text("issues")
                            .foregroundColor(.secondary)
                    }

                    Text("Number of issues to fetch on initial load. Lower values load faster but may require clicking \"Load More\" to see all issues.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text("Recommended values:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 100 - Fast initial load (recommended)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• 500 - Balanced performance")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• 1000+ - Slower but shows more issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Logs Settings Tab

struct LogsSettingsTab: View {
    var body: some View {
        Form {
            Section {
                Text("Logs")
                    .font(.headline)

                HStack {
                    Text("Log File Location:")
                        .font(.caption)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(Logger.shared.getLogFileURL().path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                HStack {
                    Spacer()
                    Button("Clear Log") {
                        Logger.shared.clearLog()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Keychain Helper

struct KeychainHelper {
    static func save(key: String, data: String) -> Bool {
        guard let data = data.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
}
