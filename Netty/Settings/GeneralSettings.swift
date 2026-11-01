import NettyKit
import SwiftUI

/// The first pane: what Netty is, how it starts, how it stays current, and who made it.
struct GeneralSettings: View {
    @Bindable var settings: NettySettings
    let launchAtLogin: LaunchAtLogin
    let updates: UpdateChecker

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                NettyMark(size: 72)
                Text("Netty").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Your network companion in the menu bar.").foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("Version \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
                    UpdateBadge(updates: updates)
                }
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

            UpdatesCard(settings: settings, updates: updates)

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

/// Netty is not notarized, so it only tells about a new version and links to it.
private struct UpdatesCard: View {
    @Bindable var settings: NettySettings
    let updates: UpdateChecker

    var body: some View {
        SettingsCard(title: "Updates", symbol: "arrow.down.circle") {
            SettingRow(title: "Check automatically",
                       detail: "Asks GitHub for the latest release and notifies you when a new version is out.") {
                Picker("Check automatically", selection: $settings.updateCheckSchedule) {
                    ForEach(UpdateCheckSchedule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            if let release = updates.available {
                SettingRow(title: "Netty \(release.version) is available",
                           detail: "Installed with Homebrew? Run brew upgrade --cask netty. Otherwise download it and replace Netty in Applications.") {
                    Button("Download") { NSWorkspace.shared.open(release.pageURL) }
                }
                if !release.highlights.isEmpty {
                    ReleaseHighlights(highlights: release.highlights)
                }
            } else {
                SettingRow(title: status, detail: lastCheck) {
                    Button("Check Now") { Task { await updates.checkNow() } }
                        .disabled(updates.isChecking)
                }
            }
        }
    }

    private var status: String {
        if updates.isChecking { return "Checking…" }
        if updates.lastCheckFailed { return "Couldn't reach GitHub" }
        return updates.lastCheck == nil ? "Not checked yet" :"Netty is up to date"
    }

    private var lastCheck: String? {
        updates.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))." }
    }
}

/// What the new version brings, from its release notes.
private struct ReleaseHighlights: View {
    let highlights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's new").font(.subheadline.weight(.semibold))
            ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
                Label {
                    Text(highlight).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkle").foregroundStyle(.tint)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Next to the version number: says a newer one is out and opens its release page.
struct UpdateBadge: View {
    let updates: UpdateChecker

    var body: some View {
        if let release = updates.available {
            Button { NSWorkspace.shared.open(release.pageURL) } label: {
                Label("\(release.version) available", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.tint.opacity(0.15)))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help("Open the release page of Netty \(release.version)")
        }
    }
}

private extension UpdateCheckSchedule {
    var title: String {
        switch self {
        case .off: "Off"
        case .every6Hours: "Every 6 hours"
        case .daily: "Every day"
        case .weekly: "Every week"
        }
    }
}
