import AppKit
import NettyKit
import SwiftUI

/// The first-run welcome window, styled like the popover: no title bar, the
/// desktop showing through. A SwiftUI `.plain` window cannot become key, so
/// Return would never reach Done; this AppKit window can.
final class WelcomeWindowController {
    private var window: NSWindow?

    func show(settings: NettySettings, location: LocationPermission, notifications: NotificationPermission,
              requestNotifications: @escaping () async -> Void) {
        let view = OnboardingView(settings: settings, location: location, notifications: notifications,
                                  requestNotifications: requestNotifications,
                                  close: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let window = KeyableBorderlessWindow(contentRect: hosting.frame, styleMask: [.borderless],
                                             backing: .buffered, defer: false)
        // Still named for Mission Control and VoiceOver.
        window.title = "Welcome to Netty"
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        // The view draws its own rounded shadow.
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        // A menu bar app is not active on its own: without this the window opens behind, its button dimmed.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETTY_FIRST_LAUNCH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("CHECK welcome canBecomeKey:", window.canBecomeKey, "isKey:", window.isKeyWindow,
                      "app active:", NSApp.isActive)
            }
        }
        #endif
    }

    func close() {
        window?.close()
        window = nil
    }
}

private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
