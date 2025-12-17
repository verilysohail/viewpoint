import SwiftUI
import AppKit

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let jiraService: JiraService
    private var viewModel: MenuBarQuickCreateViewModel?

    init(jiraService: JiraService) {
        self.jiraService = jiraService
        super.init()
    }

    func setupMenuBar() {
        Logger.shared.info("MenuBarManager: Setting up menu bar icon")

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        Logger.shared.info("MenuBarManager: Status item created: \(statusItem != nil)")

        if let button = statusItem?.button {
            Logger.shared.info("MenuBarManager: Configuring button")
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            Logger.shared.info("MenuBarManager: Button configured with image: \(image != nil)")
        } else {
            Logger.shared.error("MenuBarManager: Failed to get status item button")
        }

        // Create view model
        viewModel = MenuBarQuickCreateViewModel(jiraService: jiraService, dismissAction: {
            self.popover?.close()
        })

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 120)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarQuickCreateView(viewModel: viewModel!)
        )

        // Add delegate to handle popover lifecycle
        popover?.delegate = self
    }

    func removeMenuBar() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }

    // Note: Key event handling (Enter/Escape) is now handled by SubmittableTextField
    // which provides reliable, focus-aware event monitoring

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        // Check which mouse button was clicked
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Right-click: show menu
            showMenu()
        } else {
            // Left-click: show quick create popover
            if let popover = popover {
                if popover.isShown {
                    popover.close()
                } else {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    // Focus the popover window
                    DispatchQueue.main.async {
                        if let popoverWindow = popover.contentViewController?.view.window {
                            popoverWindow.makeKey()
                        }
                    }
                }
            }
        }
    }

    @objc private func showMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quick Create Issue", action: #selector(showQuickCreate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Viewpoint", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Viewpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Set targets
        menu.items[0].target = self
        menu.items[2].target = self
        menu.items[3].target = self

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showQuickCreate() {
        guard let button = statusItem?.button, let popover = popover else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Focus the popover window
        DispatchQueue.main.async {
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.makeKey()
            }
        }
    }

    @objc private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Open main window if no windows are visible
        if NSApp.windows.isEmpty || !NSApp.windows.contains(where: { $0.isVisible && $0.isKeyWindow }) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - NSPopoverDelegate
extension MenuBarManager: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // SubmittableTextField handles its own cleanup
    }
}
