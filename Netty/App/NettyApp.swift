import NettyKit
import SwiftUI

@main
struct NettyApp: App {
    @State private var settings: NettySettings
    @State private var monitor: ConnectionMonitor
    @State private var speedTester: SpeedTester
    @State private var location: LocationPermission
    @State private var notifier: ConnectionNotifier
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var notificationPermission = NotificationPermission()

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
        MenuBarExtra {
            PopoverContainer(monitor: monitor, speedTester: speedTester, location: location)
        } label: {
            Image(nsImage: MenuBarIconRenderer.image(for: settings.iconStyle.appearance(for: monitor.status)))
        }
        .menuBarExtraStyle(.window)

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

/// Feeds the popover and gives it SwiftUI's `openSettings`, which only views receive.
private struct PopoverContainer: View {
    let monitor: ConnectionMonitor
    let speedTester: SpeedTester
    let location: LocationPermission
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PopoverView(
            model: PopoverModel(monitor: monitor, speedTester: speedTester, location: location),
            actions: PopoverActions(
                opened: { Task { await monitor.recheck() } },
                runSpeedTest: { Task { await speedTester.run() } },
                requestWiFiName: { location.request() },
                openSettings: showSettings,
                quit: { NSApplication.shared.terminate(nil) }
            )
        )
    }

    private func showSettings() {
        // A menu bar agent is not active; bring the window to the front.
        NSApp.activate()
        openSettings()
        // The window exists on the next turn.
        DispatchQueue.main.async {
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.makeKeyAndOrderFront(nil)
        }
    }
}
