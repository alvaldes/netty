import NettyKit
import SwiftUI

/// The popover shown from the menu bar icon (design proposal A, "Pulse").
struct PopoverView: View {
    let model: PopoverModel
    var actions = PopoverActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.layout.visibleSections, id: \.self) { section in
                switch section {
                case .status: StatusHeader(model: model, openSettings: actions.openSettings)
                case .quality: MetricsRow(model: model)
                case .speed: SpeedCard(model: model, runSpeedTest: actions.runSpeedTest)
                case .network: NetworkRow(model: model, requestWiFiName: actions.requestWiFiName)
                }
            }
            if !model.layout.visibleSections.isEmpty {
                Divider()
            }
            HStack {
                // The status section holds the Settings button; without it, Settings moves here.
                if !model.layout.isVisible(.status) {
                    Button("Settings…", action: actions.openSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(",")
                        .focusEffectDisabled()
                }
                Spacer()
                Button("Quit Netty", action: actions.quit)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
                    .focusEffectDisabled()
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Status

private struct StatusHeader: View {
    let model: PopoverModel
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(model.status.color.opacity(0.16))
                Circle()
                    .fill(model.status.color)
                    .frame(width: 14, height: 14)
                    .shadow(color: model.status.color.opacity(0.8), radius: 5)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.status.title)
                    .font(.system(size: 20, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let subtitle = subtitle(now: context.date)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .card(radius: Brand.buttonRadius)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            // The popover gives its first button keyboard focus; the ring is noise here.
            .focusEffectDisabled()
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }

    private func subtitle(now: Date) -> String {
        var parts: [String] = []
        if model.statusSince == nil {
            parts.append("Testing the connection")
        } else if let since = model.statusSince, model.layout.isVisible(.statusDuration) {
            parts.append("for " + StatusDuration.text(seconds: now.timeIntervalSince(since)))
        }
        let reasons = model.degradedReasons.map(\.title)
        if !reasons.isEmpty {
            parts.append(reasons.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Quality

private struct MetricsRow: View {
    let model: PopoverModel

    var body: some View {
        Grid(horizontalSpacing: 8) {
            GridRow {
                if model.layout.isVisible(.latency) {
                    MetricTile(title: "Latency", value: milliseconds(model.metrics.latency))
                }
                if model.layout.isVisible(.jitter) {
                    MetricTile(title: "Jitter", value: milliseconds(model.metrics.jitter))
                }
                if model.layout.isVisible(.loss) {
                    MetricTile(title: "Loss", value: loss)
                }
            }
        }
    }

    private func milliseconds(_ value: Double?) -> String {
        guard model.isOnline, let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0)))) ms"
    }

    private var loss: String {
        guard model.isOnline else { return "—" }
        return "\((model.metrics.loss * 100).formatted(.number.precision(.fractionLength(0)))) %"
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .card(radius: Brand.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Speed

private struct SpeedCard: View {
    let model: PopoverModel
    let runSpeedTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Speed").font(.system(size: 13, weight: .semibold))
                Spacer()
                measuredLabel
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if model.layout.isVisible(.download) || model.layout.isVisible(.upload) {
                HStack(spacing: 8) {
                    if model.layout.isVisible(.download) {
                        SpeedValue(title: "↓ Download", mbps: model.lastSpeed?.download)
                    }
                    if model.layout.isVisible(.upload) {
                        SpeedValue(title: "↑ Upload", mbps: model.lastSpeed?.upload)
                    }
                }
            }
            if model.layout.isVisible(.responsiveness) || model.layout.isVisible(.speedTestButton) {
                speedFooter
            }
        }
        .padding(14)
        .card()
    }

    private var speedFooter: some View {
        HStack {
            if model.layout.isVisible(.responsiveness), let rpm = model.lastSpeed?.responsiveness {
                    Text("Responsiveness \(rpm.formatted(.number.precision(.fractionLength(0)))) RPM")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.layout.isVisible(.speedTestButton) {
                    Button(action: runSpeedTest) {
                        if model.isTestingSpeed {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Testing…")
                            }
                        } else {
                            Text("Run Speed Test")
                        }
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .disabled(model.isTestingSpeed || !model.isOnline)
                    .keyboardShortcut("t")
                    .focusEffectDisabled()
                }
        }
    }

    @ViewBuilder private var measuredLabel: some View {
        if model.speedTestFailed {
            Text("Last test failed")
        } else if let date = model.lastSpeed?.date {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Measured \(date, format: .relative(presentation: .named))")
            }
        } else {
            Text("No test yet")
        }
    }
}

private struct SpeedValue: View {
    let title: String
    let mbps: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(mbps.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                if mbps != nil {
                    Text("Mbps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Network

private struct NetworkRow: View {
    let model: PopoverModel
    let requestWiFiName: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.layout.isVisible(.interface) || model.layout.isVisible(.vpn) {
                interfaceLine
            }
            if showsLocal || showsPublic {
                HStack(spacing: 16) {
                    if showsLocal, let local = model.localAddress {
                        AddressLabel(title: "Local IP", address: local)
                    }
                    if showsPublic {
                        AddressLabel(title: "Public IP", address: model.publicAddress)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var showsLocal: Bool { model.layout.isVisible(.localIP) && model.localAddress != nil }
    /// Only online: offline there is nobody to ask.
    private var showsPublic: Bool { model.layout.isVisible(.publicIP) && model.isOnline }

    private var interfaceLine: some View {
        HStack(spacing: 8) {
            if model.layout.isVisible(.interface) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.system(size: 12))
                if model.canRequestWiFiName {
                    Button("Show name", action: requestWiFiName)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            Spacer()
            if model.layout.isVisible(.vpn) {
                Text(model.path?.isVPN == true ? "VPN on" : "VPN off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Brand.hairline(scheme)))
            }
        }
    }

    private var symbol: String {
        switch model.path?.interface {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .other: "network"
        case .some(.none), nil: "wifi.slash"
        }
    }

    private var name: String {
        switch model.path?.interface {
        case .wifi: model.wifiName ?? "Wi-Fi"
        case .ethernet: "Ethernet"
        case .cellular: "Cellular"
        case .other: "Other network"
        case .some(.none), nil: "No network"
        }
    }
}

/// An address that copies itself on click.
private struct AddressLabel: View {
    let title: String
    let address: String?
    @State private var copied = false

    var body: some View {
        Button {
            guard let address else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(copied ? "Copied" : title)
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                Text(address ?? "…")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(address == nil)
        .help(address == nil ? "" : "Click to copy")
        .accessibilityLabel("\(title) \(address ?? "unknown")")
        .accessibilityHint("Copies the address")
    }
}

// MARK: - Labels

extension ConnectionStatus? {
    var color: Color {
        switch self {
        case .online: .green
        case .degraded: .yellow
        case .offline: .red
        case nil: .secondary
        }
    }

    var title: String {
        switch self {
        case .online: "Online"
        case .degraded: "Degraded"
        case .offline: "Offline"
        case nil: "Checking…"
        }
    }
}

private extension DegradedReason {
    var title: String {
        switch self {
        case .latency: "high latency"
        case .jitter: "unstable latency"
        case .loss: "packet loss"
        }
    }
}
