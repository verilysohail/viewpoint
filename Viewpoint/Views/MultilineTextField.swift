import SwiftUI

/// A multi-line text field using native SwiftUI TextEditor.
/// User clicks send button to submit.
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

            // TextEditor
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .foregroundColor(.black)
                .focused($isFocused)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
        }
        .onAppear {
            isFocused = true
        }
        .background(
            // Hidden button to capture Cmd+Enter
            Button("") {
                onSubmit()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .hidden()
        )
    }
}
