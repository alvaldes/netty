import SwiftUI

struct GeneralSettings: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        SettingsCard(title: "Startup", symbol: "power") {
            SettingRow(title: "Launch at login", detail: "Start Netty when you log in to your Mac.") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.isEnabled },
                                                        set: { launchAtLogin.setEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if launchAtLogin.needsApproval {
                Divider()
                SettingRow(title: "Needs your approval",
                           detail: "Allow Netty in System Settings › General › Login Items.") {
                    Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                }
            }
            if let error = launchAtLogin.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
