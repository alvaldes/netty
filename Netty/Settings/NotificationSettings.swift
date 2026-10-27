import NettyKit
import SwiftUI

struct NotificationSettings: View {
    @Bindable var settings: NettySettings
    let permission: NotificationPermission

    var body: some View {
        SettingsCard(title: "Notifications", symbol: "bell.badge",
                     subtitle: "A degraded (yellow) connection never notifies. Focus modes are respected.") {
            SettingRow(title: "When the connection drops") {
                Toggle("When the connection drops", isOn: $settings.notifiesWhenOffline)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()
            SettingRow(title: "When it comes back", detail: "Says how long you were offline.") {
                Toggle("When it comes back", isOn: $settings.notifiesWhenBackOnline)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if permission.status == .denied {
                Divider()
                SettingRow(title: "Notifications are off for Netty", detail: "Turn them on in System Settings.") {
                    Button("Open Notifications") { permission.openSystemSettings() }
                }
            }
        }
    }
}
