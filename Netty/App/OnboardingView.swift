import NettyKit
import SwiftUI

/// First-run window: says what Netty does and asks for each permission with its reason.
struct OnboardingView: View {
    static let windowID = "onboarding"

    let settings: NettySettings
    let location: LocationPermission
    let notifications: NotificationPermission
    let requestNotifications: () async -> Void

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 22) {
            NettyMark(size: 88)

            VStack(spacing: 8) {
                Text("Know when your internet drops")
                    .font(.title2.weight(.semibold))
                Text("Netty lives in the menu bar: green when you're online, yellow when the connection is poor, red when there's no internet.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                OnboardingRow(symbol: "bell.badge", title: "Notifications",
                              detail: "Tells you when the connection drops and comes back.",
                              isGranted: notifications.status == .granted) {
                    Task {
                        await requestNotifications()
                        await notifications.refresh()
                    }
                }
                Divider()
                OnboardingRow(symbol: "wifi", title: "Wi-Fi name",
                              detail: "macOS shares it only with apps that have Location access. Netty never reads your location.",
                              isGranted: location.status == .granted) {
                    location.request()
                }
            }
            .padding(16)
            .card(radius: 14)

            Text("Both are optional, and you can change them later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Done") { finish() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 440)
        .task { await notifications.refresh() }
        // Closing the window also counts: it is not shown again.
        .onDisappear { settings.hasCompletedOnboarding = true }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        dismissWindow(id: Self.windowID)
    }
}

private struct OnboardingRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isGranted: Bool
    let allow: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: allow)
            }
        }
    }
}
