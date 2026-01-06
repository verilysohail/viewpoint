import SwiftUI

/// A multi-line text field using native SwiftUI TextEditor.
/// Enter submits, Shift+Enter adds a newline.
struct MultilineTextField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    var minHeight: CGFloat
    var maxHeight: CGFloat
    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        onSubmit: @escaping () -> Void,
        font: NSFont? = nil,  // Kept for API compatibility, not used
        minHeight: CGFloat = 36,
        maxHeight: CGFloat = 120,
        focusOnAppear: Bool = true
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color(NSColor.placeholderTextColor))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            // TextEditor with Enter key handling
            if #available(macOS 14.0, *) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .focused($isFocused)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .onKeyPress { keyPress in
                        if keyPress.key == .return && !keyPress.modifiers.contains(.shift) {
                            // Enter without Shift: submit
                            onSubmit()
                            return .handled
                        }
                        // Shift+Enter or other keys: let it pass through
                        return .ignored
                    }
            } else {
                // Fallback for macOS 13 and earlier - no Enter key handling
                // User must click the send button
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .focused($isFocused)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}
