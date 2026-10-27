import SwiftUI

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                NettyMark(size: 96)
                Text("Netty").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Your network companion in the menu bar.").foregroundStyle(.secondary)
                Text("Version \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

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
