import NettyKit
import SwiftUI

/// Show, hide and reorder the popover's sections, next to a live preview.
struct PopoverSettings: View {
    @Bindable var settings: NettySettings
    /// The popover's current content, so the preview shows real numbers.
    let previewModel: () -> PopoverModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 16) {
                SettingsCard(title: "Sections", symbol: "rectangle.stack",
                             subtitle: "Drag to reorder. Switch off a section, or just the parts you don't need.") {
                    List {
                        ForEach(settings.popoverLayout.entries, id: \.section) { entry in
                            SectionRow(section: entry.section, isVisible: visibility(of: entry.section),
                                       element: { element(visibility: $0) })
                        }
                        .onMove { settings.popoverLayout.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(settings.popoverLayout.entries.count) * 40
                        + CGFloat(PopoverElement.allCases.count) * 22)
                }
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetPopoverLayout() }
                        .disabled(settings.popoverLayout == .defaults)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("Live preview").font(.caption).foregroundStyle(.secondary)
                PopoverView(model: preview)
                    // A picture of the popover: its buttons act only in the menu bar.
                    .allowsHitTesting(false)
                    .card(radius: 16)
                    .accessibilityLabel("Preview of the popover")
            }
            .fixedSize()
        }
    }

    /// Live content in the layout being edited.
    private var preview: PopoverModel {
        var model = previewModel()
        model.layout = settings.popoverLayout
        return model
    }

    private func element(visibility element: PopoverElement) -> Binding<Bool> {
        Binding(get: { settings.popoverLayout.isSwitchedOn(element) },
                set: { settings.popoverLayout.setVisible($0, for: element) })
    }

    private func visibility(of section: PopoverSection) -> Binding<Bool> {
        Binding(get: { settings.popoverLayout.isVisible(section) },
                set: { settings.popoverLayout.setVisible($0, for: section) })
    }
}

private struct SectionRow: View {
    let section: PopoverSection
    @Binding var isVisible: Bool
    let element: (PopoverElement) -> Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                ForEach(section.elements, id: \.self) { item in
                    Toggle(item.title, isOn: element(item))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .frame(height: 18)
                        .help(item == .publicIP ? "Looked up at Cloudflare's 1.1.1.1 only while it shows." : "")
                }
                .disabled(!isVisible)
            }
            Spacer(minLength: 8)
            Toggle(section.title, isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private extension PopoverSection {
    var title: String {
        switch self {
        case .status: "Status"
        case .quality: "Quality"
        case .speed: "Speed"
        case .network: "Network"
        }
    }

}

private extension PopoverElement {
    var title: String {
        switch self {
        case .statusDuration: "How long it has lasted"
        case .latency: "Latency"
        case .jitter: "Jitter"
        case .loss: "Packet loss"
        case .download: "Download"
        case .upload: "Upload"
        case .responsiveness: "Responsiveness"
        case .speedTestButton: "Run Speed Test button"
        case .interface: "Wi-Fi or interface"
        case .vpn: "VPN"
        case .localIP: "Local IP"
        case .publicIP: "Public IP"
        }
    }
}
