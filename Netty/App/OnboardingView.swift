import NettyKit
import SwiftUI

/// First-run window: says what Netty does and asks for each permission with its reason.
struct OnboardingView: View {
    let settings: NettySettings
    let location: LocationPermission
    let notifications: NotificationPermission
    let requestNotifications: () async -> Void
    let close: () -> Void

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
                .focusEffectDisabled()
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 440)
        // The popover's look: the desktop shows through, rounded, a hairline and a soft shadow.
        // SwiftUI's materials blend within the window, which has nothing behind; this blends behind it.
        .background(BehindWindowMaterial(material: .popover))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.12)))
        .clipShape(.rect(cornerRadius: 26))
        .padding(24)
        .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
        .task { await notifications.refresh() }
        // No close button without a title bar: Escape closes, as Done does.
        .onExitCommand { finish() }
        // A menu bar app is not active on its own: without this the window opens behind, its button dimmed.
        // Closing the window also counts: it is not shown again.
        .onDisappear { settings.hasCompletedOnboarding = true }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        close()
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
                    // Return and the Done button already lead; a ring on Allow distracts.
                    .focusEffectDisabled()
            }
        }
    }
}

/// `NSVisualEffectView` blending with what is behind the window, as a popover does.
private struct BehindWindowMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
