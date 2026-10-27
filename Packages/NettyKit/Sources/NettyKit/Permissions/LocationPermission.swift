import AppKit
import CoreLocation
import Observation

/// The system services the location permission depends on, replaceable in tests.
public struct LocationClient {
    public var status: () -> LocationPermission.Status
    public var request: () -> Void
    public var openSystemSettings: () -> Void
    /// Yields whenever the authorization may have changed.
    public var changes: () -> AsyncStream<Void>

    public init(
        status: @escaping () -> LocationPermission.Status,
        request: @escaping () -> Void,
        openSystemSettings: @escaping () -> Void,
        changes: @escaping () -> AsyncStream<Void>
    ) {
        self.status = status
        self.request = request
        self.openSystemSettings = openSystemSettings
        self.changes = changes
    }

    public static var live: LocationClient {
        let authorization = LocationAuthorization()
        return LocationClient(
            status: { authorization.status },
            request: { authorization.manager.requestWhenInUseAuthorization() },
            openSystemSettings: {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
                NSWorkspace.shared.open(url)
            },
            changes: { authorization.changes }
        )
    }
}

/// Observable Location Services permission state for the UI.
///
/// macOS reveals the Wi-Fi network name only to apps with Location access.
/// Netty never reads the location itself.
@Observable
public final class LocationPermission {
    nonisolated public enum Status: Sendable, Equatable {
        case notDetermined, granted, denied
    }

    public private(set) var status: Status
    /// Called after `status` changes, e.g. to re-read the Wi-Fi name.
    public var onChange: ((Status) -> Void)?

    private let client: LocationClient

    public init(client: LocationClient = .live) {
        self.client = client
        status = client.status()
    }

    /// Shows the system prompt the first time; afterwards only System Settings can change it.
    public func request() {
        switch status {
        case .notDetermined: client.request()
        case .denied: client.openSystemSettings()
        case .granted: break
        }
    }

    /// Keeps `status` in sync with System Settings until the task is cancelled.
    public func monitor() async {
        for await _ in client.changes() {
            let newStatus = client.status()
            guard newStatus != status else { continue }
            status = newStatus
            onChange?(newStatus)
        }
    }
}

/// Owns the `CLLocationManager`, which reports authorization changes to its delegate.
private final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    override init() {
        (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
        manager.delegate = self
    }

    var status: LocationPermission.Status {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .granted
        default: .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield()
    }
}
