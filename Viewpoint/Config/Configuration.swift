import Foundation

struct Configuration {
    static let shared = Configuration()

    let jiraBaseURL: String
    let jiraEmail: String
    let jiraAPIKey: String

    private init() {
        // Load from .env file
        // Try multiple possible locations
        let possiblePaths = [
            // Current directory
            FileManager.default.currentDirectoryPath + "/.env",
            // Parent directory (for when running from build folder)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent()
                .appendingPathComponent(".env")
                .path,
            // Project root (assuming we're in DerivedData)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env")
                .path,
            // Hardcoded path for development
            "/Users/smamdani/code/viewpoint/.env"
        ]

        var envPath = ""
        for path in possiblePaths {
            print("Checking for .env at: \(path)")
            if FileManager.default.fileExists(atPath: path) {
                envPath = path
                print("Found .env file at: \(path)")
                break
            }
        }

        var envVars: [String: String] = [:]

        if !envPath.isEmpty {
            print("Attempting to read .env from: \(envPath)")
            if let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
                print("Successfully read .env file, length: \(contents.count)")
                print("File contents:\n\(contents)")

                let lines = contents.components(separatedBy: .newlines)
                print("Found \(lines.count) lines")

                for line in lines {
                    print("Processing line: '\(line)'")
                    let parts = line.components(separatedBy: " = ")
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        print("  Parsed: \(key) = \(value.prefix(20))...")
                        envVars[key] = value
                    }
                }
            } else {
                print("Failed to read .env file!")
            }
        } else {
            print("No .env file found in any location!")
        }

        self.jiraBaseURL = envVars["JIRA_BASE_URL"] ?? ""
        self.jiraEmail = envVars["JIRA_EMAIL"] ?? ""
        self.jiraAPIKey = envVars["JIRA_API_KEY"] ?? ""

        // Debug logging
        print("\n=== Configuration loaded ===")
        print("  Base URL: '\(self.jiraBaseURL)'")
        print("  Email: '\(self.jiraEmail)'")
        print("  API Key present: \(!self.jiraAPIKey.isEmpty)")
        print("  ENV file path: \(envPath)")
        print("  Parsed vars: \(envVars.keys)")
        print("===========================\n")
    }
}
