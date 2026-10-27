import Foundation
import NettyKit

/// Everything the popover shows, as plain values: the view never reads the
/// monitors directly, so it can be rendered with sample data.
struct PopoverModel {
    var status: ConnectionStatus?
    var statusSince: Date?
    var degradedReasons: [DegradedReason] = []
    var metrics = QualityMetrics.empty
    var lastSpeed: SpeedTestResult?
    var isTestingSpeed = false
    var speedTestFailed = false
    var path: NetworkPath?
    var wifiName: String?
    /// Wi-Fi is up but its name is hidden until Location access is granted.
    var canRequestWiFiName = false
    /// The Mac's address on the network in use.
    var localAddress: String?
    /// The public IP; `nil` while unknown.
    var publicAddress: String?
    /// Which sections show, in which order.
    var layout = PopoverLayout.defaults

    var isOnline: Bool { status == .online || status == .degraded }
}

/// What the popover's controls do.
struct PopoverActions {
    var runSpeedTest: () -> Void = {}
    var requestWiFiName: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

extension PopoverModel {
    init(monitor: ConnectionMonitor, speedTester: SpeedTester, location: LocationPermission,
         publicAddress: PublicAddress, layout: PopoverLayout) {
        self.init(
            status: monitor.status,
            statusSince: monitor.statusSince,
            degradedReasons: monitor.status == .degraded ? monitor.metrics.degradedReasons(under: monitor.rules) : [],
            metrics: monitor.metrics,
            lastSpeed: speedTester.lastResult,
            isTestingSpeed: speedTester.isRunning,
            speedTestFailed: speedTester.lastError != nil,
            path: monitor.path,
            wifiName: monitor.wifiName,
            canRequestWiFiName: monitor.path?.interface == .wifi && location.status != .granted,
            localAddress: monitor.localAddress,
            publicAddress: publicAddress.address,
            layout: layout
        )
    }
}
