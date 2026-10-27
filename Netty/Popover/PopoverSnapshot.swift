#if DEBUG
import AppKit
import NettyKit
import SwiftUI

/// Debug only: renders the popover in each status, light and dark, to PNG files
/// in an offscreen window that is never shown, so the design can be reviewed
/// without opening the app. Run with `NETTY_RENDER_POPOVER=<directory>`.
enum PopoverSnapshot {
    static func renderIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["NETTY_RENDER_POPOVER"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, model) in samples {
            for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                render(PopoverView(model: model), appearance: appearance,
                       to: output.appending(path: "\(name)-\(scheme).png"))
            }
        }
        exit(0)
    }

    static var samples: [(String, PopoverModel)] {
        let speed = SpeedTestResult(download: 9.2, upload: 19.5, responsiveness: 61, bytesTransferred: 43_000_000,
                                    date: .now.addingTimeInterval(-12 * 60))
        let wifi = NetworkPath(isSatisfied: true, interface: .wifi, isExpensive: false, isConstrained: false)
        let online = PopoverModel(status: .online, statusSince: .now.addingTimeInterval(-8_040),
                                  metrics: QualityMetrics(latency: 24, jitter: 3, loss: 0),
                                  lastSpeed: speed, path: wifi, wifiName: "Home",
                                  // Documentation addresses (RFC 1918 and RFC 5737).
                                  localAddress: "192.168.0.103", publicAddress: "203.0.113.7")
        var degraded = online
        degraded.status = .degraded
        degraded.statusSince = .now.addingTimeInterval(-180)
        degraded.metrics = QualityMetrics(latency: 182, jitter: 41, loss: 0)
        degraded.degradedReasons = [.latency]
        degraded.isTestingSpeed = true
        var offline = online
        offline.status = .offline
        offline.statusSince = .now.addingTimeInterval(-45)
        offline.metrics = .empty
        offline.wifiName = nil
        offline.canRequestWiFiName = true
        offline.lastSpeed = nil
        var custom = online
        custom.layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        custom.layout.setVisible(false, for: .status)
        custom.layout.setVisible(false, for: .quality)
        var elements = online
        for element: PopoverElement in [.jitter, .loss, .vpn, .localIP, .publicIP, .responsiveness] {
            elements.layout.setVisible(false, for: element)
        }
        return [("online", online), ("degraded", degraded), ("offline", offline), ("custom-layout", custom),
                ("only-latency", elements)]
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle its first layout pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
