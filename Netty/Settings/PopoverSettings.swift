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
                             subtitle: "Drag to reorder. Switch off what you don't need.") {
                    List {
                        ForEach(settings.popoverLayout.entries, id: \.section) { entry in
                            SectionRow(section: entry.section, isVisible: visibility(of: entry.section))
                        }
                        .onMove { settings.popoverLayout.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(settings.popoverLayout.entries.count) * 52)
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

    private func visibility(of section: PopoverSection) -> Binding<Bool> {
        Binding(get: { settings.popoverLayout.isVisible(section) },
                set: { settings.popoverLayout.setVisible($0, for: section) })
    }
}

private struct SectionRow: View {
    let section: PopoverSection
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                Text(section.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    var detail: String {
        switch self {
        case .status: "Color and for how long"
        case .quality: "Latency, jitter, loss"
        case .speed: "Last test and its button"
        case .network: "Wi-Fi or interface, VPN"
        }
    }
}
