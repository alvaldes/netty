import NettyKit
import SwiftUI

/// The rules behind the icon's colors, each explained for people who have
/// never heard of latency or jitter.
struct ConnectionSettings: View {
    @Bindable var settings: NettySettings

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Checks", symbol: "dot.radiowaves.left.and.right",
                         subtitle: "Netty checks whether the internet itself answers, not just your Wi-Fi: a network without internet or a hotel sign-in page counts as offline.") {
                SettingRow(title: "Check every",
                           detail: "How often Netty asks the internet for an answer. Opening the popover also checks right away.") {
                    Picker("Check every", selection: $settings.probeInterval) {
                        ForEach(NettySettings.probeIntervals, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(title: "Degraded (yellow) when", symbol: "exclamationmark.triangle",
                         subtitle: "You are online, but the connection is poor. Any one of these turns the icon yellow.") {
                RuleRow(title: "Latency at least",
                        detail: "Latency is how long a round trip to the internet takes, in milliseconds (ms). Lower is better: under 50 ms feels instant; above 150 ms, video calls and games start to lag. Netty uses the middle value of the recent checks, so one slow answer does not count.",
                        value: rule(\.latencyThreshold), range: 50...1000, step: 10, unit: "ms")
                Divider()
                RuleRow(title: "Jitter at least",
                        detail: "Jitter is how much the latency jumps from one check to the next. A steady connection stays under 30 ms; high jitter makes calls choppy and robotic even when latency looks fine.",
                        value: rule(\.jitterThreshold), range: 10...500, step: 5, unit: "ms")
                Divider()
                RuleRow(title: "Packet loss at least",
                        detail: "Packet loss is the share of checks that got no answer at all. A healthy connection loses none; with loss, pages stall and calls drop words.",
                        value: lossPercent, range: 5...100, step: 5, unit: "%")
                Divider()
                RuleRow(title: "Measured over the last",
                        detail: "How many recent checks these numbers come from: \(windowDuration) at the current check interval. More checks react slower but steadier.",
                        value: count(\.windowSize), range: 3...30, step: 1, unit: "checks")
            }

            SettingsCard(title: "Offline (red) and back", symbol: "wifi.exclamationmark",
                         subtitle: "Waiting for a few checks in a row keeps one lost answer from flipping the icon.") {
                RuleRow(title: "Offline after",
                        detail: "Failed checks in a row before the icon turns red. Fewer reacts faster, but a short hiccup may look like an outage.",
                        value: count(\.failuresToOffline), range: 1...10, step: 1, unit: "failed checks")
                Divider()
                RuleRow(title: "Online again after",
                        detail: "Good checks in a row before red turns back to green or yellow.",
                        value: count(\.successesToOnline), range: 1...10, step: 1, unit: "good checks")
                Divider()
                RuleRow(title: "Green again after",
                        detail: "Checks in a row under every yellow limit before yellow turns back to green, so the icon does not flicker.",
                        value: count(\.evaluationsToRecover), range: 1...10, step: 1, unit: "clean checks")
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") { settings.resetQualityRules() }
                    .disabled(settings.qualityRules == .defaults)
            }
        }
    }

    /// How long the measuring window lasts, e.g. "the last minute".
    private var windowDuration: String {
        let seconds = Double(settings.qualityRules.windowSize * settings.probeInterval)
        return "about " + StatusDuration.text(seconds: seconds)
    }

    private func rule(_ keyPath: WritableKeyPath<QualityRules, Double>) -> Binding<Double> {
        Binding(get: { settings.qualityRules[keyPath: keyPath] },
                set: { settings.qualityRules[keyPath: keyPath] = $0 })
    }

    private func count(_ keyPath: WritableKeyPath<QualityRules, Int>) -> Binding<Double> {
        Binding(get: { Double(settings.qualityRules[keyPath: keyPath]) },
                set: { settings.qualityRules[keyPath: keyPath] = Int($0) })
    }

    private var lossPercent: Binding<Double> {
        Binding(get: { (settings.qualityRules.lossThreshold * 100).rounded() },
                set: { settings.qualityRules.lossThreshold = $0 / 100 })
    }
}

private struct RuleRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Stepper(value: $value, in: range, step: step) {
                Text("\(value.formatted(.number.precision(.fractionLength(0)))) \(unit)")
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }
}
