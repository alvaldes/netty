import NettyKit
import SwiftUI

@main
struct NettyApp: App {
    @State private var monitor: ConnectionMonitor
    @State private var speedTester: SpeedTester
    @State private var location: LocationPermission

    init() {
        let monitor = ConnectionMonitor()
        let speedTester = SpeedTester(conditions: {
            SpeedTestConditions(
                isOnline: monitor.status == .online || monitor.status == .degraded,
                isMetered: monitor.path.map { $0.isExpensive || $0.isConstrained } ?? false
            )
        })
        _monitor = State(initialValue: monitor)
        _speedTester = State(initialValue: speedTester)
        let location = LocationPermission()
        location.onChange = { _ in monitor.refreshNetworkInfo() }
        _location = State(initialValue: location)
        // Probe and keep the speed test schedule for the whole app lifetime.
        Task { await monitor.run() }
        Task { await speedTester.runSchedule() }
        Task { await location.monitor() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, speedTester: speedTester, location: location)
        } label: {
            Image(systemName: monitor.status.symbolName)
        }
    }
}

// Placeholder until the popover design pass (T6) and the configurable icon (T8).
private struct MenuContent: View {
    let monitor: ConnectionMonitor
    let speedTester: SpeedTester
    let location: LocationPermission

    var body: some View {
        Text(monitor.status.title)
        if let latency = monitor.metrics.latency {
            Text("Latency \(latency, format: .number.precision(.fractionLength(0))) ms")
        }
        if speedTester.isRunning {
            Text("Testing speed…")
        } else if let result = speedTester.lastResult {
            Text("↓ \(result.download, format: .number.precision(.fractionLength(1))) Mbps  ↑ \(result.upload, format: .number.precision(.fractionLength(1))) Mbps")
            Text("Measured \(result.date, format: .relative(presentation: .named))")
        }
        if let network = networkDescription {
            Text(network)
        }
        if monitor.path?.isVPN == true {
            Text("VPN on")
        }
        Divider()
        if monitor.path?.interface == .wifi, location.status != .granted {
            Button("Show Wi-Fi Name…") { location.request() }
        }
        Button("Re-check Now") { Task { await monitor.recheck() } }
        Button("Run Speed Test") { Task { await speedTester.run() } }
            .disabled(speedTester.isRunning)
        Button("Quit Netty") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private extension MenuContent {
    var networkDescription: String? {
        guard let interface = monitor.path?.interface else { return nil }
        return switch interface {
        case .wifi: monitor.wifiName.map { "Wi-Fi: \($0)" } ?? "Wi-Fi"
        case .ethernet: "Ethernet"
        case .cellular: "Cellular"
        case .other: "Other network"
        case .none: nil
        }
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

    var title: String {
        switch self {
        case .online: "Online"
        case .degraded: "Degraded"
        case .offline: "Offline"
        case nil: "Checking…"
        }
    }
}
