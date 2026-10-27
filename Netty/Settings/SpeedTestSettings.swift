import NettyKit
import SwiftUI

struct SpeedTestSettings: View {
    @Bindable var settings: NettySettings

    var body: some View {
        SettingsCard(title: "Speed Test", symbol: "speedometer",
                     subtitle: "Uses Apple's built-in networkQuality. Each test runs for up to 20 seconds and can use hundreds of MB on a fast connection.") {
            SettingRow(title: "Run automatically", detail: "Run Speed Test in the popover always works.") {
                Picker("Run automatically", selection: $settings.speedTestSchedule) {
                    ForEach(SpeedTestSchedule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingRow(title: "Skip metered networks",
                       detail: "No automatic tests on an iPhone hotspot or in Low Data Mode.") {
                Toggle("Skip metered networks", isOn: $settings.skipsMeteredNetworks)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .disabled(settings.speedTestSchedule == .off)
        }
    }
}

private extension SpeedTestSchedule {
    var title: String {
        switch self {
        case .off: "Off"
        case .hourly: "Every hour"
        case .every6Hours: "Every 6 hours"
        case .daily: "Every day"
        }
    }
}
