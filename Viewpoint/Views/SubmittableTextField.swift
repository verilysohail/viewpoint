import SwiftUI
import AppKit

/// A TextField wrapper that reliably handles Enter/Return key submission on macOS.
/// Supports multi-line text with wrapping and dynamic height.
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
    var minHeight: CGFloat
    var maxHeight: CGFloat

    init(
        _ placeholder: String,
        text: Binding<String>,
        onSubmit: @escaping () -> Void,
        onEscape: (() -> Void)? = nil,
        font: NSFont? = nil,
        textColor: NSColor? = nil,
        backgroundColor: NSColor? = nil,
        isBordered: Bool = false,
        focusOnAppear: Bool = true,
        minHeight: CGFloat = 36,
        maxHeight: CGFloat = 120
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
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SubmittableNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 8

        // Configure appearance
        if let font = font {
            textView.font = font
        } else {
            textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
        if let textColor = textColor {
            textView.textColor = textColor
        }
        if let backgroundColor = backgroundColor {
            textView.backgroundColor = backgroundColor
        } else {
            textView.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        }

        // Set callbacks and initial text
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.string = text
        textView.placeholderString = placeholder

        // Focus on appear if requested
        if focusOnAppear {
            textView.shouldFocusOnAppear = true
        }

        scrollView.documentView = textView

        // Store reference to coordinator for height updates
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SubmittableNSTextView else { return }

        if textView.string != text {
            textView.string = text
            textView.updatePlaceholder()
        }
        textView.placeholderString = placeholder
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape

        if let font = font {
            textView.font = font
        }
        if let textColor = textColor {
            textView.textColor = textColor
        }

        // Update height
        context.coordinator.updateHeight()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubmittableTextField
        weak var scrollView: NSScrollView?
        weak var textView: SubmittableNSTextView?

        init(_ parent: SubmittableTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
                (textView as? SubmittableNSTextView)?.updatePlaceholder()
                updateHeight()
            }
        }

        func updateHeight() {
            guard let textView = textView,
                  let scrollView = scrollView else { return }

            // Calculate the required height for the text
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)

                // Add padding for top/bottom
                let contentHeight = usedRect.height + 16

                // Clamp between min and max height
                let newHeight = min(max(contentHeight, parent.minHeight), parent.maxHeight)

                // Update the scroll view's height constraint if needed
                if let constraint = scrollView.constraints.first(where: { $0.firstAttribute == .height }) {
                    if constraint.constant != newHeight {
                        constraint.constant = newHeight
                    }
                } else {
                    let heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: newHeight)
                    heightConstraint.priority = .defaultHigh
                    heightConstraint.isActive = true
                }

                // Enable scrolling if content exceeds max height
                scrollView.hasVerticalScroller = contentHeight > parent.maxHeight
            }
        }
    }
}

/// Custom NSTextView that reliably handles Enter/Return and Escape keys
class SubmittableNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var shouldFocusOnAppear: Bool = false
    var placeholderString: String = ""
    private var hasFocused: Bool = false
    private var placeholderLabel: NSTextField?

    convenience init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        self.init(frame: .zero, textContainer: textContainer)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlaceholder()
    }

    private func setupPlaceholder() {
        let label = NSTextField(labelWithString: "")
        label.textColor = .placeholderTextColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        placeholderLabel = label
    }

    func updatePlaceholder() {
        placeholderLabel?.stringValue = placeholderString
        placeholderLabel?.isHidden = !string.isEmpty
    }

    override var string: String {
        didSet {
            updatePlaceholder()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Focus the text view if requested (and not already done)
            if shouldFocusOnAppear && !hasFocused {
                hasFocused = true
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let window = self.window else { return }
                    window.makeKey()
                    window.makeFirstResponder(self)
                }
            }
        }

        updatePlaceholder()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return or Enter (keypad)
            // Check for Shift modifier - allow Shift+Enter for newlines
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onSubmit?()
            }
        case 53: // Escape
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        updatePlaceholder()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        updatePlaceholder()
        return result
    }
}
