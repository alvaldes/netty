import AppKit
import SwiftUI

/// A card in the JUMP style: a flat, top-lit surface with a hairline border.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .card(radius: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(radius: 16)
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 10, y: 4)
    }
}

/// A label with an optional explanation on the left, its control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// Netty's mark: the status dot with its halo, as the popover shows it.
struct NettyMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.16))
            Circle()
                .fill(Color.green)
                .frame(width: size * 0.4, height: size * 0.4)
                .shadow(color: .green.opacity(0.8), radius: size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Shapes the hosting window: names it without showing the name, which the
/// sidebar already does, and makes its title bar transparent.
struct WindowChrome: NSViewRepresentable {
    static let titleBarHeight: CGFloat = 28

    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view joins its window after this pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Still named for Mission Control, the Window menu and VoiceOver.
            window.title = title
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

enum AppVersion {
    static let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
}
