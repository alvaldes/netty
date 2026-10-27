import NettyKit
import SwiftUI

@main
struct NettyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var settings: NettySettings
    @State private var monitor: ConnectionMonitor
    @State private var speedTester: SpeedTester
    @State private var location: LocationPermission
    @State private var notifier: ConnectionNotifier
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var notificationPermission = NotificationPermission()
    private let statusItem = StatusItemHolder()

    init() {
        var defaults = UserDefaults.standard
        #if DEBUG
        PopoverSnapshot.renderIfRequested()
        SettingsSnapshot.renderIfRequested()
        MenuBarSnapshot.renderGlyphsIfRequested()
        MenuBarSnapshot.captureIfRequested()
        // Snapshot runs must not touch the user's settings.
        if MenuBarSnapshot.requestedStyle != nil, let volatile = UserDefaults(suiteName: "com.alvaldes.netty.snapshot") {
            defaults = volatile
        }
        #endif
        let settings = NettySettings(defaults: defaults)
        #if DEBUG
        if let style = MenuBarSnapshot.requestedStyle { settings.iconStyle = style }
        #endif
        let monitor = ConnectionMonitor()
        let speedTester = SpeedTester(conditions: {
            SpeedTestConditions(
                isOnline: monitor.status == .online || monitor.status == .degraded,
                isMetered: monitor.path.map { $0.isExpensive || $0.isConstrained } ?? false
            )
        })
        let location = LocationPermission()
        location.onChange = { _ in monitor.refreshNetworkInfo() }
        let notifier = ConnectionNotifier()
        monitor.onStatusChange = { old, new, date in notifier.statusChanged(from: old, to: new, at: date) }

        func apply() {
            monitor.rules = settings.qualityRules
            monitor.probeInterval = .seconds(settings.probeInterval)
            speedTester.schedule = settings.speedTestSchedule
            speedTester.skipsMeteredNetworks = settings.skipsMeteredNetworks
            notifier.notifiesWhenOffline = settings.notifiesWhenOffline
            notifier.notifiesWhenBackOnline = settings.notifiesWhenBackOnline
        }
        apply()
        settings.onChange = apply

        _settings = State(initialValue: settings)
        _monitor = State(initialValue: monitor)
        _speedTester = State(initialValue: speedTester)
        _location = State(initialValue: location)
        _notifier = State(initialValue: notifier)
        // The status bar takes items once the app has finished launching.
        let holder = statusItem
        DispatchQueue.main.async {
            holder.controller = StatusItemController(settings: settings, monitor: monitor,
                                                     speedTester: speedTester, location: location)
            #if DEBUG
            holder.controller?.checkClicksIfRequested()
            #endif
        }
        // Probe, keep the speed test schedule and follow Location access for the whole app lifetime.
        Task { await monitor.run() }
        Task { await speedTester.runSchedule() }
        Task { await location.monitor() }
        // The first launch asks in the welcome window, with the reason; later
        // launches only register Netty's presenter (no prompt once decided).
        if settings.hasCompletedOnboarding {
            Task { await notifier.requestAuthorization() }
        }
    }

    var body: some Scene {
        Window("Welcome to Netty", id: OnboardingView.windowID) {
            OnboardingView(settings: settings, location: location, notifications: notificationPermission,
                           requestNotifications: { await notifier.requestAuthorization() })
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(settings.hasCompletedOnboarding ? .suppressed : .presented)

        Settings {
            SettingsView(settings: settings, launchAtLogin: launchAtLogin, location: location,
                         notifications: notificationPermission)
        }
    }
}

/// A menu bar app has no main window: closing the popover or Settings must not
/// quit it, as SwiftUI does when the last window closes.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Keeps the menu bar item alive for the app's lifetime.
private final class StatusItemHolder {
    var controller: StatusItemController?
}
