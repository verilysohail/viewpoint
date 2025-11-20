import SwiftUI

struct SettingsView: View {
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

                TextField("Jira Base URL", text: $jiraBaseURL)
                    .textFieldStyle(.roundedBorder)
                Text("Example: https://your-company.atlassian.net")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Email", text: $jiraEmail)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $jiraAPIKey)
                    .textFieldStyle(.roundedBorder)

                Link("How to create an API key", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    .font(.caption)
            }

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
        .padding(20)
        .frame(width: 500, height: 450)
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
