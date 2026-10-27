import NettyKit
import SwiftUI

@main
struct NettyApp: App {
    @State private var monitor: ConnectionMonitor

    init() {
        let monitor = ConnectionMonitor()
        _monitor = State(initialValue: monitor)
        // Probe for the whole app lifetime.
        Task { await monitor.run() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            Image(systemName: monitor.status.symbolName)
        }
    }
}

// Placeholder until the popover design pass (T6) and the configurable icon (T8).
private struct MenuContent: View {
    let monitor: ConnectionMonitor

    var body: some View {
        Text(monitor.status.title)
        if let latency = monitor.metrics.latency {
            Text("Latency \(latency, format: .number.precision(.fractionLength(0))) ms")
        }
        Divider()
        Button("Re-check Now") { Task { await monitor.recheck() } }
        Button("Quit Netty") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
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
