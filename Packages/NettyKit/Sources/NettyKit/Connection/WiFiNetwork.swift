import CoreWLAN

nonisolated enum WiFiNetwork {
    /// The current Wi-Fi network name; `nil` when not on Wi-Fi or without Location access.
    static func currentName() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}
