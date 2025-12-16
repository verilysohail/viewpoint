import SwiftUI
import AppKit

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let jiraService: JiraService
    private var eventMonitor: Any?
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
            self.stopMonitoringKeyEvents()
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
        stopMonitoringKeyEvents()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }

    private func startMonitoringKeyEvents() {
        // Remove existing monitor if any
        stopMonitoringKeyEvents()

        // Monitor local key events in the popover
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let popover = self.popover,
                  popover.isShown else {
                return event
            }

            // Check if Enter/Return was pressed
            if event.keyCode == 36 || event.keyCode == 76 { // 36 = Return, 76 = Enter
                // Directly trigger the create issue action
                if let vm = self.viewModel, !vm.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { @MainActor in
                        vm.createIssue()
                    }
                    return nil // Consume the event only if we handled it
                }
            }

            // Check if Escape was pressed
            if event.keyCode == 53 { // Escape
                popover.close()
                return nil
            }

            return event
        }
    }

    private func stopMonitoringKeyEvents() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Recursively find the first NSTextField in a view hierarchy
    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }

        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }

        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }

        return nil
    }

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
                    // Start monitoring BEFORE showing popover to catch all key events
                    self.startMonitoringKeyEvents()
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    // Focus the popover and make it the first responder
                    DispatchQueue.main.async {
                        if let popoverWindow = popover.contentViewController?.view.window {
                            popoverWindow.makeKey()
                            // Find and focus the text field inside the popover
                            if let textField = self.findTextField(in: popover.contentViewController?.view) {
                                popoverWindow.makeFirstResponder(textField)
                            } else {
                                popoverWindow.makeFirstResponder(popover.contentViewController?.view)
                            }
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
        // Start monitoring BEFORE showing popover to catch all key events
        self.startMonitoringKeyEvents()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Focus the popover and make it the first responder
        DispatchQueue.main.async {
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.makeKey()
                // Find and focus the text field inside the popover
                if let textField = self.findTextField(in: popover.contentViewController?.view) {
                    popoverWindow.makeFirstResponder(textField)
                } else {
                    popoverWindow.makeFirstResponder(popover.contentViewController?.view)
                }
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
        stopMonitoringKeyEvents()
    }
}
