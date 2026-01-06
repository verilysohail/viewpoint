import SwiftUI
import AppKit

/// A TextField wrapper that reliably handles Enter/Return key submission on macOS.
/// SwiftUI's .onSubmit is unreliable, so this uses NSTextField with proper event monitoring.
struct SubmittableTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    var onEscape: (() -> Void)?
    var font: NSFont?
    var textColor: NSColor?
    var backgroundColor: NSColor?
    var isBordered: Bool
    var focusOnAppear: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        onSubmit: @escaping () -> Void,
        onEscape: (() -> Void)? = nil,
        font: NSFont? = nil,
        textColor: NSColor? = nil,
        backgroundColor: NSColor? = nil,
        isBordered: Bool = false,
        focusOnAppear: Bool = true
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
        self.onEscape = onEscape
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.isBordered = isBordered
        self.focusOnAppear = focusOnAppear
    }

    func makeNSView(context: Context) -> SubmittableNSTextField {
        let textField = SubmittableNSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.isBordered = isBordered
        textField.drawsBackground = backgroundColor != nil
        textField.focusRingType = .none

        if let font = font {
            textField.font = font
        }
        if let textColor = textColor {
            textField.textColor = textColor
        }
        if let backgroundColor = backgroundColor {
            textField.backgroundColor = backgroundColor
        }

        // Set callbacks
        textField.onSubmit = onSubmit
        textField.onEscape = onEscape

        // Focus on appear if requested
        if focusOnAppear {
            textField.shouldFocusOnAppear = true
        }

        return textField
    }

    func updateNSView(_ nsView: SubmittableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.onSubmit = onSubmit
        nsView.onEscape = onEscape

        if let font = font {
            nsView.font = font
        }
        if let textColor = textColor {
            nsView.textColor = textColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SubmittableTextField

        init(_ parent: SubmittableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

/// Custom NSTextField that reliably handles Enter/Return and Escape keys
class SubmittableNSTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var shouldFocusOnAppear: Bool = false
    private var eventMonitor: Any?
    private var hasFocused: Bool = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Remove old monitor if exists
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Add local event monitor when we're in a window
        if window != nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // Only handle if this text field is the first responder
                guard self.window?.firstResponder == self.currentEditor() else {
                    return event
                }

                switch event.keyCode {
                case 36, 76: // Return or Enter (keypad)
                    self.onSubmit?()
                    return nil // Consume the event
                case 53: // Escape
                    self.onEscape?()
                    return nil // Consume the event
                default:
                    break
                }

                return event
            }

            // Focus the text field if requested (and not already done)
            if shouldFocusOnAppear && !hasFocused {
                hasFocused = true
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let window = self.window else { return }
                    // Make the window key first, then focus the text field
                    window.makeKey()
                    window.makeFirstResponder(self)
                }
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // Select all text when becoming first responder (standard macOS behavior)
        if result {
            currentEditor()?.selectAll(nil)
        }
        return result
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
