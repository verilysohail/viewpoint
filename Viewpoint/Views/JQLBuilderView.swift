import SwiftUI

struct JQLBuilderView: View {
    @ObservedObject var jiraService: JiraService
    @State private var jqlText: String = ""
    @State private var suggestions: [JQLSuggestion] = []
    @State private var showSuggestions: Bool = false
    @State private var selectedSuggestionIndex: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // JQL Text Field
            HStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                ZStack {
                    TextField("Enter JQL query (e.g., project = \"SETI\" AND status != Done)", text: $jqlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .focused($isFocused)
                        .onChange(of: jqlText) { _ in
                            updateSuggestions()
                        }
                        .onSubmit {
                            if showSuggestions && !suggestions.isEmpty {
                                applySuggestion(suggestions[selectedSuggestionIndex])
                            } else {
                                executeSearch()
                            }
                        }

                    // Invisible overlay to capture key events
                    KeyEventHandlingView(
                        onUpArrow: {
                            if showSuggestions && !suggestions.isEmpty {
                                selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
                            }
                        },
                        onDownArrow: {
                            if showSuggestions && !suggestions.isEmpty {
                                selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
                            }
                        },
                        onEscape: {
                            showSuggestions = false
                            selectedSuggestionIndex = 0
                        }
                    )
                }

                if !jqlText.isEmpty {
                    Button(action: {
                        jqlText = ""
                        suggestions = []
                        showSuggestions = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Clear JQL")
                }

                Button(action: executeSearch) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Execute JQL Query")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )

            // Autocomplete Suggestions
            if showSuggestions && !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            Button(action: {
                                applySuggestion(suggestion)
                            }) {
                                HStack(spacing: 8) {
                                    // Type indicator
                                    Image(systemName: iconForSuggestionType(suggestion.type))
                                        .font(.system(size: 11))
                                        .foregroundColor(colorForSuggestionType(suggestion.type))
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.displayText)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.primary)

                                        if let description = suggestion.description {
                                            Text(description)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == selectedSuggestionIndex ? Color.blue.opacity(0.15) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < suggestions.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.top, 4)
            }
        }
        .onAppear {
            // Initialize with current JQL from service if it exists
            if let currentJQL = jiraService.currentJQL, !currentJQL.isEmpty {
                jqlText = currentJQL
            }
        }
        .onChange(of: jiraService.currentJQL) { newValue in
            // Update text field when service's JQL changes (e.g., from Indigo)
            if let newJQL = newValue, newJQL != jqlText {
                jqlText = newJQL
            }
        }
    }

    // MARK: - Autocomplete Logic

    private func updateSuggestions() {
        let context = determineContext()
        suggestions = generateSuggestions(for: context)
        showSuggestions = !suggestions.isEmpty && isFocused
        selectedSuggestionIndex = 0

        Logger.shared.info("Context: \(context), Suggestions count: \(suggestions.count), Will show: \(showSuggestions)")
        if suggestions.count > 0 && suggestions.count <= 5 {
            Logger.shared.info("Suggestions: \(suggestions.map { $0.text }.joined(separator: ", "))")
        }
    }

    private func determineContext() -> JQLTokenContext {
        // Empty or just started
        if jqlText.isEmpty {
            return .field
        }

        // Tokenize the current JQL
        let tokens = tokenize(jqlText)

        guard !tokens.isEmpty else {
            return .field
        }

        // Check if text ends with space - this means we're ready for next token
        let endsWithSpace = jqlText.hasSuffix(" ")

        // Get the text without trailing space for analysis
        let trimmedText = jqlText.trimmingCharacters(in: .whitespaces)
        let trimmedTokens = tokenize(trimmedText)

        if endsWithSpace {
            // User just pressed space - show suggestions for NEXT token
            guard let lastToken = trimmedTokens.last else {
                return .field
            }

            // Check if last token is a field name -> suggest operators
            if JQLField.find(name: lastToken) != nil {
                Logger.shared.info("After field '\(lastToken)' - suggesting operators")
                return .operator
            }

            // Check if last token is an operator -> suggest values
            let operators = ["=", "!=", "IN", ">", "<", ">=", "<=", "~", "!~", "WAS", "CHANGED"]
            if operators.contains(lastToken.uppercased()) {
                Logger.shared.info("After operator '\(lastToken)' - suggesting values")
                return .value
            }

            // Handle "NOT IN" - check last two tokens
            if trimmedTokens.count >= 2 {
                let lastTwo = "\(trimmedTokens[trimmedTokens.count - 2]) \(trimmedTokens[trimmedTokens.count - 1])"
                if operators.contains(lastTwo.uppercased()) {
                    Logger.shared.info("After operator '\(lastTwo)' - suggesting values")
                    return .value
                }
            }

            // Check if last token is a value (quoted or looks complete) -> suggest conjunction
            if trimmedTokens.count >= 3 || lastToken.hasPrefix("\"") {
                Logger.shared.info("After value - suggesting conjunction")
                return .conjunction
            }

            return .field
        } else {
            // User is typing (no trailing space) - complete the current token
            let lastToken = tokens.last!

            // If typing after a conjunction, suggest field
            if JQLKeyword.conjunctions.contains(lastToken.uppercased()) {
                return .field
            }

            // Check if we're after a field + space + typing operator
            if trimmedTokens.count >= 2 {
                let secondToLast = trimmedTokens[trimmedTokens.count - 2]
                if JQLField.find(name: secondToLast) != nil {
                    Logger.shared.info("Typing operator after field '\(secondToLast)'")
                    return .operator
                }
            }

            // Check if we're after field + operator + space + typing value
            if trimmedTokens.count >= 3 {
                let thirdToLast = trimmedTokens[trimmedTokens.count - 3]
                let secondToLast = trimmedTokens[trimmedTokens.count - 2]
                let operators = ["=", "!=", "IN", ">", "<", ">=", "<=", "~", "!~"]

                if JQLField.find(name: thirdToLast) != nil && operators.contains(secondToLast.uppercased()) {
                    Logger.shared.info("Typing value after operator '\(secondToLast)'")
                    return .value
                }
            }

            // Default: typing a field name
            return .field
        }
    }

    private func generateSuggestions(for context: JQLTokenContext) -> [JQLSuggestion] {
        let currentInput = getCurrentToken().lowercased()

        switch context {
        case .field:
            return JQLField.allFields
                .filter { field in
                    currentInput.isEmpty ||
                    field.name.lowercased().contains(currentInput) ||
                    field.aliases.contains(where: { $0.lowercased().contains(currentInput) })
                }
                .map { field in
                    JQLSuggestion(
                        text: field.name,
                        type: .field,
                        description: field.description
                    )
                }

        case .operator:
            guard let fieldName = getPreviousFieldName(),
                  let field = JQLField.find(name: fieldName) else {
                return []
            }

            return field.operators
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .map { op in
                    JQLSuggestion(
                        text: op,
                        type: .operator,
                        description: nil
                    )
                }

        case .value:
            return generateValueSuggestions(currentInput: currentInput)

        case .conjunction:
            let keywords = JQLKeyword.conjunctions + [JQLKeyword.orderBy]
            return keywords
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .map { keyword in
                    JQLSuggestion(
                        text: keyword,
                        type: .keyword,
                        description: nil
                    )
                }
        }
    }

    private func generateValueSuggestions(currentInput: String) -> [JQLSuggestion] {
        guard let fieldName = getPreviousFieldName(),
              let field = JQLField.find(name: fieldName) else {
            return []
        }

        var suggestions: [JQLSuggestion] = []

        // Add special values for user fields
        if field.valueType == .user {
            suggestions.append(JQLSuggestion(
                text: "currentUser()",
                type: .value,
                description: "The currently logged in user"
            ))
        }

        // Add values from available data
        switch field.name.lowercased() {
        case "project":
            suggestions += jiraService.availableProjects
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .sorted()
                .map { project in
                    JQLSuggestion(
                        text: "\"\(project)\"",
                        displayText: project,
                        type: .value,
                        description: nil
                    )
                }

        case "status":
            suggestions += jiraService.availableStatuses
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .sorted()
                .map { status in
                    JQLSuggestion(
                        text: "\"\(status)\"",
                        displayText: status,
                        type: .value,
                        description: nil
                    )
                }

        case "statuscategory":
            suggestions += JQLKeyword.statusCategories
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .map { category in
                    JQLSuggestion(
                        text: "\"\(category)\"",
                        displayText: category,
                        type: .value,
                        description: nil
                    )
                }

        case "assignee":
            suggestions += jiraService.availableAssignees
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .sorted()
                .map { assignee in
                    JQLSuggestion(
                        text: "\"\(assignee)\"",
                        displayText: assignee,
                        type: .value,
                        description: nil
                    )
                }

        case "type", "issuetype":
            suggestions += jiraService.availableIssueTypes
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .sorted()
                .map { type in
                    JQLSuggestion(
                        text: "\"\(type)\"",
                        displayText: type,
                        type: .value,
                        description: nil
                    )
                }

        case "component", "components":
            suggestions += jiraService.availableComponents
                .filter { currentInput.isEmpty || $0.lowercased().contains(currentInput) }
                .sorted()
                .map { component in
                    JQLSuggestion(
                        text: "\"\(component)\"",
                        displayText: component,
                        type: .value,
                        description: nil
                    )
                }

        case "sprint":
            suggestions += jiraService.availableSprints
                .filter { sprint in
                    currentInput.isEmpty ||
                    sprint.name.lowercased().contains(currentInput) ||
                    String(sprint.id).contains(currentInput)
                }
                .sorted { $0.id > $1.id }
                .map { sprint in
                    JQLSuggestion(
                        text: String(sprint.id),
                        displayText: "\(sprint.name) (ID: \(sprint.id))",
                        type: .value,
                        description: sprint.state
                    )
                }

        default:
            break
        }

        return suggestions
    }

    private func getCurrentToken() -> String {
        // If ends with space, we're starting a new token, so current token is empty
        if jqlText.hasSuffix(" ") {
            return ""
        }

        // Otherwise, get the last token
        let trimmed = jqlText.trimmingCharacters(in: .whitespaces)
        let tokens = tokenize(trimmed)
        return tokens.last ?? ""
    }

    private func getPreviousFieldName() -> String? {
        // Use trimmed text to avoid trailing spaces
        let trimmedText = jqlText.trimmingCharacters(in: .whitespaces)
        let tokens = tokenize(trimmedText)

        Logger.shared.info("getPreviousFieldName - tokens: \(tokens)")

        // Look backward for the most recent field name
        for token in tokens.reversed() {
            if let field = JQLField.find(name: token) {
                Logger.shared.info("Found field: \(field.name)")
                return token
            }
        }

        Logger.shared.info("No field found in tokens")
        return nil
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        var inQuotes = false
        var quoteChar: Character?

        for char in text {
            if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                    quoteChar = nil
                    currentToken.append(char)
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                    currentToken.append(char)
                } else {
                    currentToken.append(char)
                }
            } else if char == " " && !inQuotes {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else {
                currentToken.append(char)
            }
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }

    private func applySuggestion(_ suggestion: JQLSuggestion) {
        // Remove the current incomplete token
        let tokens = tokenize(jqlText)
        var newJQL = jqlText

        // If we're replacing the last token (typing without trailing space)
        if let lastToken = tokens.last, !jqlText.hasSuffix(" ") {
            if let range = newJQL.range(of: lastToken, options: .backwards) {
                newJQL.removeSubrange(range)
            }
        }

        // Add the suggestion text (NO automatic space - user presses space to continue)
        newJQL += suggestion.text

        jqlText = newJQL

        // Close suggestions after selection
        showSuggestions = false
        selectedSuggestionIndex = 0

        // Keep focus on the text field
        isFocused = true
    }

    private func executeSearch() {
        showSuggestions = false
        let trimmedJQL = jqlText.trimmingCharacters(in: .whitespaces)

        guard !trimmedJQL.isEmpty else { return }

        Task {
            await jiraService.searchWithJQL(trimmedJQL)
        }
    }

    // MARK: - UI Helpers

    private func iconForSuggestionType(_ type: JQLSuggestion.SuggestionType) -> String {
        switch type {
        case .field: return "textformat"
        case .operator: return "equal.circle"
        case .value: return "text.quote"
        case .keyword: return "character.cursor.ibeam"
        }
    }

    private func colorForSuggestionType(_ type: JQLSuggestion.SuggestionType) -> Color {
        switch type {
        case .field: return .blue
        case .operator: return .orange
        case .value: return .green
        case .keyword: return .purple
        }
    }
}

// MARK: - Key Event Handling

struct KeyEventHandlingView: NSViewRepresentable {
    let onUpArrow: () -> Void
    let onDownArrow: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerView()
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyHandlerView {
            view.onUpArrow = onUpArrow
            view.onDownArrow = onDownArrow
            view.onEscape = onEscape
        }
    }

    class KeyHandlerView: NSView {
        var onUpArrow: (() -> Void)?
        var onDownArrow: (() -> Void)?
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: // Up arrow
                onUpArrow?()
            case 125: // Down arrow
                onDownArrow?()
            case 53: // Escape
                onEscape?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}
