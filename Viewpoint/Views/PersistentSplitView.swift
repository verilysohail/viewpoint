import SwiftUI
import AppKit

struct PersistentSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let top: Top
    let bottom: Bottom
    @Binding var position: Double

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = CustomSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .paneSplitter
        splitView.delegate = context.coordinator

        let topHostingView = NSHostingView(rootView: top)
        let bottomHostingView = NSHostingView(rootView: bottom)

        topHostingView.translatesAutoresizingMaskIntoConstraints = false
        bottomHostingView.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(topHostingView)
        splitView.addArrangedSubview(bottomHostingView)

        // Set initial position after a small delay to ensure views are laid out
        DispatchQueue.main.async {
            if splitView.bounds.height > 0 && context.coordinator.position > 0 {
                splitView.setPosition(context.coordinator.position, ofDividerAt: 0)
            }
        }

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        // Update hosting views
        if nsView.subviews.count >= 2 {
            if let topHost = nsView.subviews[0] as? NSHostingView<Top> {
                topHost.rootView = top
            }
            if let bottomHost = nsView.subviews[1] as? NSHostingView<Bottom> {
                bottomHost.rootView = bottom
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(position: $position)
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        @Binding var position: Double

        init(position: Binding<Double>) {
            _position = position
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count == 2 else { return }

            let topView = splitView.subviews[0]
            let newPosition = topView.frame.height
            if newPosition > 0 {
                position = newPosition
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 100 // Minimum height for top pane
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.height - 200 // Minimum height for bottom pane
        }

        func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
            // Allow the bottom view to resize, keep top view fixed during window resize
            return view == splitView.subviews.last
        }
    }
}

// MARK: - Custom Split View with Dark Gray Divider

class CustomSplitView: NSSplitView {
    override var dividerColor: NSColor {
        return NSColor.darkGray
    }

    override var dividerThickness: CGFloat {
        return 6.0
    }
}
