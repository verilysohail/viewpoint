import Foundation

struct Configuration {
    static let shared = Configuration()

    let jiraBaseURL: String
    let jiraEmail: String
    let jiraAPIKey: String

    private init() {
        // Try to load from UserDefaults and Keychain first
        let savedBaseURL = UserDefaults.standard.string(forKey: "jiraBaseURL") ?? ""
        let savedEmail = UserDefaults.standard.string(forKey: "jiraEmail") ?? ""
        let savedAPIKey = KeychainHelper.load(key: "jiraAPIKey") ?? ""

        // If settings are found in UserDefaults/Keychain, use them
        if !savedBaseURL.isEmpty && !savedEmail.isEmpty && !savedAPIKey.isEmpty {
            self.jiraBaseURL = savedBaseURL
            self.jiraEmail = savedEmail
            self.jiraAPIKey = savedAPIKey

            print("\n=== Configuration loaded from UserDefaults/Keychain ===")
            print("  Base URL: '\(self.jiraBaseURL)'")
            print("  Email: '\(self.jiraEmail)'")
            print("  API Key present: \(!self.jiraAPIKey.isEmpty)")
            print("=======================================================\n")
            return
        }

        // Fallback to .env file for development
        let possiblePaths = [
            FileManager.default.currentDirectoryPath + "/.env",
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent()
                .appendingPathComponent(".env")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env")
                .path,
            "/Users/smamdani/code/viewpoint/.env"
        ]

        var envPath = ""
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                envPath = path
                print("Found .env file at: \(path)")
                break
            }
        }

        var envVars: [String: String] = [:]

        if !envPath.isEmpty {
            if let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
                let lines = contents.components(separatedBy: .newlines)

                for line in lines {
                    let parts = line.components(separatedBy: " = ")
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        envVars[key] = value
                    }
                }
            }
        }

        self.jiraBaseURL = envVars["JIRA_BASE_URL"] ?? ""
        self.jiraEmail = envVars["JIRA_EMAIL"] ?? ""
        self.jiraAPIKey = envVars["JIRA_API_KEY"] ?? ""

        print("\n=== Configuration loaded from .env ===")
        print("  Base URL: '\(self.jiraBaseURL)'")
        print("  Email: '\(self.jiraEmail)'")
        print("  API Key present: \(!self.jiraAPIKey.isEmpty)")
        print("======================================\n")
    }
}
