import Foundation

struct PromptContent: Codable {
    let identity: String
    let answeringQuestions: String
    let guidelines: String
    let closing: String
}

class PromptLoader {
    static let shared = PromptLoader()

    let content: PromptContent

    private init() {
        if let url = Bundle.main.url(forResource: "IndigoPrompt", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PromptContent.self, from: data) {
            content = decoded
            Logger.shared.info("Loaded prompt content from IndigoPrompt.json")
        } else {
            // Fallback to hardcoded defaults if bundle resource is missing
            Logger.shared.warning("IndigoPrompt.json not found in bundle, using hardcoded defaults")
            content = PromptContent(
                identity: "You are Indigo, an AI assistant for Jira integrated into Viewpoint, a macOS Jira client.\n\nYour role is to help users manage their Jira issues using natural language. You can search for issues, update fields, create new issues, log work, and more.",
                answeringQuestions: "When the user asks questions about selected issues (e.g., \"what is this about?\", \"summarize this\"), use the SELECTED ISSUE DETAILS above to answer directly. Be conversational and helpful.",
                guidelines: "- Always explain what you're doing in plain language alongside the action\n- When closing/resolving issues, include both status and resolution fields\n- For time logging, convert durations to seconds (1h = 3600, 2h = 7200, etc.)\n- For estimates, pass time strings like \"2h\" or \"30m\" directly\n- Use \"currentUser()\" in JQL for the current user's issues\n- Be concise and helpful",
                closing: "Respond naturally and help the user accomplish their Jira tasks efficiently."
            )
        }
    }
}
