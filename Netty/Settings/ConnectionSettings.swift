import NettyKit
import SwiftUI

struct ConnectionSettings: View {
    @Bindable var settings: NettySettings

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Checks", symbol: "dot.radiowaves.left.and.right",
                         subtitle: "Netty asks Apple's captive portal check whether the internet answers.") {
                SettingRow(title: "Check every", detail: "Opening the popover also checks right away.") {
                    Picker("Check every", selection: $settings.probeInterval) {
                        ForEach(NettySettings.probeIntervals, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(title: "Degraded (yellow) when", symbol: "exclamationmark.triangle",
                         subtitle: "Any one of these over the last checks turns the icon yellow.") {
                RuleRow(title: "Median latency at least", value: rule(\.latencyThreshold), range: 50...1000, step: 10, unit: "ms")
                Divider()
                RuleRow(title: "Jitter at least", value: rule(\.jitterThreshold), range: 10...500, step: 5, unit: "ms")
                Divider()
                RuleRow(title: "Packet loss at least", value: lossPercent, range: 5...100, step: 5, unit: "%")
                Divider()
                RuleRow(title: "Measured over the last", value: count(\.windowSize), range: 3...30, step: 1, unit: "checks")
            }

            SettingsCard(title: "Offline (red) and back", symbol: "wifi.exclamationmark",
                         subtitle: "Waiting for a few checks keeps one lost answer from flipping the icon.") {
                RuleRow(title: "Offline after", value: count(\.failuresToOffline), range: 1...10, step: 1, unit: "failed checks")
                Divider()
                RuleRow(title: "Online again after", value: count(\.successesToOnline), range: 1...10, step: 1, unit: "good checks")
                Divider()
                RuleRow(title: "Green again after", value: count(\.evaluationsToRecover), range: 1...10, step: 1, unit: "clean checks")
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") { settings.resetQualityRules() }
                    .disabled(settings.qualityRules == .defaults)
            }
        }
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
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        SettingRow(title: title) {
            Stepper(value: $value, in: range, step: step) {
                Text("\(value.formatted(.number.precision(.fractionLength(0)))) \(unit)")
                    .monospacedDigit()
            }
        }
    }
}
