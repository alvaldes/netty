import AppKit
import NettyKit
import SwiftUI

/// Owns Netty's menu bar item: draws the icon and turns each click into the
/// action the user chose. `MenuBarExtra` only knows the left click, so the
/// item, its popover and its menu are AppKit's.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let settingsOpener = SettingsOpener()
    private let settings: NettySettings
    private let monitor: ConnectionMonitor
    private let speedTester: SpeedTester
    /// When the popover last closed: a click on the icon closes a transient
    /// popover on mouse-down, before the action runs on mouse-up.
    private var popoverClosedAt = Date.distantPast

    init(settings: NettySettings, monitor: ConnectionMonitor, speedTester: SpeedTester, location: LocationPermission) {
        self.settings = settings
        self.monitor = monitor
        self.speedTester = speedTester
        super.init()

        let opener = settingsOpener
        let content = PopoverContainer(settings: settings, monitor: monitor, speedTester: speedTester, location: location,
                                       openSettings: { [weak self] in
                                           self?.popover.close()
                                           opener.open()
                                       })
        let hosting = NSHostingController(rootView: content)
        // The popover follows the content's size.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // SwiftUI hands `openSettings` only to views; the item lends it one.
            let lender = NSHostingView(rootView: SettingsOpenerView(opener: settingsOpener))
            lender.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
            button.addSubview(lender)
        }
        updateIcon()
    }

    // MARK: - Icon

    /// Redraws the icon whenever the status or the icon style changes.
    private func updateIcon() {
        withObservationTracking {
            statusItem.button?.image = MenuBarIconRenderer.image(for: settings.iconStyle.appearance(for: monitor.status))
        } onChange: {
            // Called before the change lands: redraw on the next turn.
            Task { @MainActor [weak self] in self?.updateIcon() }
        }
    }

    // MARK: - Clicks

    @objc private func clicked() {
        let event = NSApp.currentEvent
        // A Control-click is a right click on a Mac.
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        let behavior = settings.clickBehavior
        perform(isRight ? behavior.right : behavior.left)
    }

    private func perform(_ action: ClickAction) {
        switch action {
        case .showPopover: togglePopover()
        case .showMenu: showMenu()
        case .runSpeedTest: Task { await speedTester.run() }
        case .openSettings: settingsOpener.open()
        }
    }

    /// `NSPopover.isShown` can stay true after the popover closed; its window cannot.
    private var isPopoverVisible: Bool {
        popover.contentViewController?.view.window?.isVisible == true
    }

    private func togglePopover() {
        guard !isPopoverVisible else {
            popover.close()
            return
        }
        // This very click already closed it.
        guard Date().timeIntervalSince(popoverClosedAt) > 0.3 else { return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Key, so the popover's keyboard shortcuts work.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        if settings.clickBehavior.menuIncludesPopover {
            menu.addItem(item("Show Netty", action: #selector(showPopoverFromMenu)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Settings…", action: #selector(openSettingsFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Netty", action: #selector(quit), key: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showPopoverFromMenu() { togglePopover() }
    @objc private func openSettingsFromMenu() { settingsOpener.open() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - NSPopoverDelegate

    /// Opening the popover is the re-check: it shows fresh numbers.
    func popoverWillShow(_ notification: Notification) {
        Task { await monitor.recheck() }
    }

    func popoverDidClose(_ notification: Notification) {
        popoverClosedAt = Date()
    }
}

/// Opens Settings in front, with the `openSettings` a view lent it.
final class SettingsOpener {
    fileprivate var action: OpenSettingsAction?

    func open() {
        // A menu bar agent is not active; bring the window to the front.
        NSApp.activate()
        action?()
        // The window exists on the next turn.
        DispatchQueue.main.async {
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct SettingsOpenerView: View {
    let opener: SettingsOpener
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { opener.action = openSettings }
    }
}

/// Feeds the popover from the live services.
private struct PopoverContainer: View {
    let settings: NettySettings
    let monitor: ConnectionMonitor
    let speedTester: SpeedTester
    let location: LocationPermission
    let openSettings: () -> Void

    var body: some View {
        PopoverView(
            model: PopoverModel(monitor: monitor, speedTester: speedTester, location: location,
                                layout: settings.popoverLayout),
            actions: PopoverActions(
                runSpeedTest: { Task { await speedTester.run() } },
                requestWiFiName: { location.request() },
                openSettings: openSettings,
                quit: { NSApp.terminate(nil) }
            )
        )
    }
}

#if DEBUG
extension StatusItemController {
    /// Debug only: runs the click actions without a mouse and reports what
    /// opened, then quits. Run with `NETTY_CHECK_CLICKS=<directory>`; the real
    /// popover is saved there as `popover.png`.
    func checkClicksIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["NETTY_CHECK_CLICKS"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            perform(.showPopover)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                print("CHECK popover shown:", isPopoverVisible)
                if let view = popover.contentViewController?.view,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: directory).appending(path: "popover.png"))
                    print("CHECK popover size:", view.bounds.size)
                }
                perform(.showPopover)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                    // The close animates first.
                    print("CHECK popover closed on second click:", !isPopoverVisible)
                    // A click a moment later opens it again.
                    perform(.showPopover)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                    print("CHECK popover reopened on third click:", isPopoverVisible)
                    perform(.openSettings)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let settings = NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
                    print("CHECK settings open:", settings?.isVisible == true, "key:", settings?.isKeyWindow == true)
                    exit(0)
                }
            }
        }
    }
}
#endif
