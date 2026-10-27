import NettyKit
import SwiftUI

struct PermissionsSettings: View {
    let location: LocationPermission
    let notifications: NotificationPermission

    var body: some View {
        SettingsCard(title: "Permissions", symbol: "lock.shield",
                     subtitle: "Netty works without them; each one only adds something to the popover.") {
            SettingRow(title: "Location",
                       detail: "macOS shares the Wi-Fi name only with apps that have Location access. Netty never reads your location.") {
                PermissionControl(isGranted: location.status == .granted,
                                  actionTitle: location.status == .denied ? "Open System Settings" : "Allow",
                                  action: { location.request() })
            }
            Divider()
            SettingRow(title: "Notifications", detail: "Tells you when the connection drops and comes back.") {
                PermissionControl(isGranted: notifications.status == .granted,
                                  actionTitle: "Open System Settings",
                                  action: { notifications.openSystemSettings() })
            }
        }
    }
}

private struct PermissionControl: View {
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        if isGranted {
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button(actionTitle, action: action)
        }
    }
}
