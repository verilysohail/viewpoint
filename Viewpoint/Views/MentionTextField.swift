import SwiftUI
import AppKit

/// A text field that supports @ mentions with autocomplete functionality
struct MentionTextField: View {
    let placeholder: String
    @Binding var text: String
    let jiraService: JiraService
    let onSubmit: () -> Void

    @State private var showingAutocomplete = false
    @State private var autocompleteSuggestions: [(displayName: String, accountId: String, email: String)] = []
    @State private var currentMentionQuery = ""
    @State private var mentionStartPosition: String.Index?
    @State private var selectedSuggestionIndex = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text field with custom key event handling
            KeyEventHandlingTextField(
                placeholder: placeholder,
                text: $text,
                onKeyDown: handleKeyDown
            )
            .font(.system(size: 13))
            .frame(height: 40)
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .focused($isFocused)
            .onChange(of: text) { newValue in
                handleTextChange(newValue)
            }

            // Autocomplete suggestions overlay
            if showingAutocomplete && !autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(autocompleteSuggestions.enumerated()), id: \.offset) { index, user in
                        Button(action: {
                            insertMention(user.displayName)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 14))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                    if !user.email.isEmpty {
                                        Text(user.email)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(index == selectedSuggestionIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < autocompleteSuggestions.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                .padding(.top, 4)
                .frame(maxHeight: 200)
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Handle Enter/Return for submission when autocomplete is closed
        if !showingAutocomplete && (event.keyCode == 36 || event.keyCode == 76) {
            onSubmit()
            return true
        }

        guard showingAutocomplete && !autocompleteSuggestions.isEmpty else {
            return false // Let the event propagate
        }

        switch event.keyCode {
        case 125: // Down arrow
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, autocompleteSuggestions.count - 1)
            return true // Event handled
        case 126: // Up arrow
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, 0)
            return true // Event handled
        case 36, 76: // Return/Enter
            if selectedSuggestionIndex < autocompleteSuggestions.count {
                insertMention(autocompleteSuggestions[selectedSuggestionIndex].displayName)
                return true // Event handled
            }
            return false
        case 48: // Tab
            if selectedSuggestionIndex < autocompleteSuggestions.count {
                insertMention(autocompleteSuggestions[selectedSuggestionIndex].displayName)
                return true // Event handled
            }
            return false
        case 53: // Escape
            showingAutocomplete = false
            mentionStartPosition = nil
            return true // Event handled
        default:
            return false // Let the event propagate
        }
    }

    private func handleTextChange(_ newValue: String) {
        // Check if the last character typed is @
        if let lastChar = newValue.last, lastChar == "@" {
            mentionStartPosition = newValue.index(before: newValue.endIndex)
            currentMentionQuery = ""
            showingAutocomplete = true
            selectedSuggestionIndex = 0
            fetchSuggestions(query: "")
        } else if showingAutocomplete, let startPos = mentionStartPosition {
            // Validate that startPos is still valid in the new text
            guard startPos < newValue.endIndex else {
                showingAutocomplete = false
                mentionStartPosition = nil
                return
            }

            // Safely extract the text after @
            guard newValue.index(after: startPos) <= newValue.endIndex else {
                showingAutocomplete = false
                mentionStartPosition = nil
                return
            }

            let afterAt = String(newValue[newValue.index(after: startPos)...])

            // Check if there's a space or newline - if so, close autocomplete
            if afterAt.contains(" ") || afterAt.contains("\n") {
                showingAutocomplete = false
                mentionStartPosition = nil
                return
            }

            currentMentionQuery = afterAt
            fetchSuggestions(query: afterAt)
        }
    }

    private func fetchSuggestions(query: String) {
        Task {
            let users = await jiraService.searchUsers(query: query)
            await MainActor.run {
                autocompleteSuggestions = users
                selectedSuggestionIndex = 0
            }
        }
    }

    private func insertMention(_ mention: String) {
        guard let startPos = mentionStartPosition else { return }

        // Ensure startPos is valid
        guard startPos < text.endIndex else {
            showingAutocomplete = false
            mentionStartPosition = nil
            return
        }

        // Replace from @ to current cursor position with the mention
        let beforeAt = String(text[..<startPos])

        // Safely get the text after @
        var afterMention = ""
        if text.index(after: startPos) < text.endIndex {
            let afterAt = text[text.index(after: startPos)...]
            afterMention = String(afterAt.drop(while: { $0 != " " && $0 != "\n" }))
        }

        text = beforeAt + "@" + mention + " " + afterMention

        // Reset autocomplete state
        showingAutocomplete = false
        mentionStartPosition = nil
        currentMentionQuery = ""
        autocompleteSuggestions = []

        // Refocus the text field
        isFocused = true
    }
}

// MARK: - Custom TextField with Key Event Handling

struct KeyEventHandlingTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        // Replace the default NSTextView with our custom one
        let textView = KeyInterceptingTextView()
        textView.keyDownHandler = context.coordinator.onKeyDown

        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isRichText = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.drawsBackground = false

        // Set placeholder
        if text.isEmpty {
            textView.string = ""
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? KeyInterceptingTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.keyDownHandler = onKeyDown
        context.coordinator.onKeyDown = onKeyDown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onKeyDown: onKeyDown)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onKeyDown: (NSEvent) -> Bool

        init(text: Binding<String>, onKeyDown: @escaping (NSEvent) -> Bool) {
            _text = text
            self.onKeyDown = onKeyDown
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // This is called for special keys, but we need to override keyDown for arrow keys
            return false
        }
    }
}

// Custom NSTextView subclass to intercept key events
class KeyInterceptingTextView: NSTextView {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if let handler = keyDownHandler, handler(event) {
            // Event was handled, don't call super
            return
        }
        super.keyDown(with: event)
    }
}
