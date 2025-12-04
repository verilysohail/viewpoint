import SwiftUI
import AppKit

class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let jiraService: JiraService

    init(jiraService: JiraService) {
        self.jiraService = jiraService
    }

    func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use SF Symbol for a colorful plus icon
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                .applying(.init(paletteColors: [
                    .systemBlue,
                    .systemGreen
                ]))

            let image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Quick Create Issue")
            button.image = image?.withSymbolConfiguration(config)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 120)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarQuickCreateView(jiraService: jiraService, dismissAction: {
                self.popover?.close()
            })
        )
    }

    func removeMenuBar() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover = popover {
            if popover.isShown {
                popover.close()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Focus the popover
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}
