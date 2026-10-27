import NettyKit
import SwiftUI

@main
struct NettyApp: App {
    @State private var monitor: ConnectionMonitor
    @State private var speedTester: SpeedTester
    @State private var location: LocationPermission
    @State private var notifier: ConnectionNotifier

    init() {
        #if DEBUG
        PopoverSnapshot.renderIfRequested()
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
        _notifier = State(initialValue: notifier)
        _monitor = State(initialValue: monitor)
        _speedTester = State(initialValue: speedTester)
        _location = State(initialValue: location)
        // Probe, keep the speed test schedule and follow Location access for the whole app lifetime.
        Task { await monitor.run() }
        Task { await speedTester.runSchedule() }
        Task { await location.monitor() }
        Task { await notifier.requestAuthorization() }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                model: PopoverModel(monitor: monitor, speedTester: speedTester, location: location),
                actions: PopoverActions(
                    opened: { Task { await monitor.recheck() } },
                    runSpeedTest: { Task { await speedTester.run() } },
                    requestWiFiName: { location.request() },
                    quit: { NSApplication.shared.terminate(nil) }
                )
            )
        } label: {
            // Placeholder until the configurable icon (T8).
            Image(systemName: monitor.status.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}

private extension ConnectionStatus? {
    var symbolName: String {
        switch self {
        case .online: "circle.fill"
        case .degraded: "circle.lefthalf.filled"
        case .offline: "circle.dotted"
        case nil: "circle"
        }
    }
}
