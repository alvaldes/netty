import SwiftUI

/// The first pane: what Netty is, how it starts, and who made it.
struct GeneralSettings: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                NettyMark(size: 72)
                Text("Netty").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Your network companion in the menu bar.").foregroundStyle(.secondary)
                Text("Version \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

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

            SettingsCard(title: "Credits", symbol: "heart") {
                LinkRow(title: "Created by", label: "@alvaldes", url: "https://alvaldes.vercel.app")
                Divider()
                LinkRow(title: "License", label: "GPL-3.0", url: "https://www.gnu.org/licenses/gpl-3.0.html")
                Divider()
                LinkRow(title: "Source code", label: "github.com/alvaldes/netty", url: "https://github.com/alvaldes/netty")
                Divider()
                LinkRow(title: "Feedback", label: "Report an issue", url: "https://github.com/alvaldes/netty/issues")
            }
        }
    }
}

private struct LinkRow: View {
    let title: String
    let label: String
    let url: String

    var body: some View {
        SettingRow(title: title) {
            if let destination = URL(string: url) {
                Link(label, destination: destination)
            }
        }
    }
}
