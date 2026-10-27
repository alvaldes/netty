import AppKit
import Observation
import UserNotifications

/// Whether macOS lets Netty show notifications, for the Permissions pane.
@Observable
final class NotificationPermission {
    enum Status {
        case notDetermined, granted, denied
    }

    private(set) var status = Status.notDetermined

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .granted
        }
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.alvaldes.netty")!
        NSWorkspace.shared.open(url)
    }
}
