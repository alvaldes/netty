import AppKit
import NettyKit
import SwiftUI
import UniformTypeIdentifiers

struct IconSettings: View {
    @Bindable var settings: NettySettings
    var customIcons = CustomIconStore()

    @State private var importError: String?

    private static let statuses: [(String, ConnectionStatus)] = [
        ("Online", .online), ("Degraded", .degraded), ("Offline", .offline),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // What changes the icon first, next to the preview; clicks do not change it.
            VStack(spacing: 16) {
                SettingsCard(title: "Style", symbol: "paintpalette") {
                    SettingRow(title: "Mode", detail: modeDetail) {
                        Picker("Mode", selection: $settings.iconStyle.mode) {
                            Text("Color").tag(MenuBarIconStyle.Mode.color)
                            Text("Black & White").tag(MenuBarIconStyle.Mode.monochrome)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    Divider()
                    SettingRow(title: "Size") {
                        HStack {
                            Slider(value: $settings.iconStyle.size, in: MenuBarIconStyle.sizeRange, step: 1)
                                .frame(width: 160)
                            Text("\(Int(settings.iconStyle.size)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                SettingsCard(title: "Glyphs", symbol: "circle.dotted.circle",
                             subtitle: "Choose a glyph for each status, or import your own SVG, PDF or PNG.") {
                    ForEach(Array(Self.statuses.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        SettingRow(title: item.0) {
                            glyphMenu(for: item.1)
                        }
                    }
                    if let importError {
                        Text(importError).font(.caption).foregroundStyle(.red)
                    }
                }
                SettingsCard(title: "Clicks", symbol: "cursorarrow.click.2",
                             subtitle: "The quick menu has Settings and Quit. Control-click counts as a right click.") {
                    SettingRow(title: "Left click") {
                        clickPicker("Left click", selection: $settings.clickBehavior.left)
                    }
                    Divider()
                    SettingRow(title: "Right click",
                               detail: "One click always opens the popover or the quick menu, so Quit stays in reach.") {
                        clickPicker("Right click", selection: $settings.clickBehavior.right)
                    }
                }

            }
            .frame(maxWidth: .infinity)

            // Beside the controls, so every change shows without scrolling.
            VStack(alignment: .leading, spacing: 8) {
                Text("Live preview").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.statuses, id: \.0) { title, status in
                        HStack(spacing: 10) {
                            IconPreview(appearance: settings.iconStyle.appearance(for: status), customIcons: customIcons)
                            Text(title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .card(radius: 16)
            }
            .fixedSize()
        }
    }

    private func clickPicker(_ title: String, selection: Binding<ClickAction>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ClickAction.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var modeDetail: String {
        switch settings.iconStyle.mode {
        case .color: "One glyph in green, yellow or red."
        case .monochrome: "Matches the menu bar; each status needs its own shape."
        }
    }

    private var glyphs: Binding<StatusGlyphs> {
        switch settings.iconStyle.mode {
        case .color: $settings.iconStyle.colorGlyphs
        case .monochrome: $settings.iconStyle.monochromeGlyphs
        }
    }

    private func glyphMenu(for status: ConnectionStatus) -> some View {
        // What the icon draws, so a saved character shows as the symbol it falls back to.
        let current = settings.iconStyle.appearance(for: status).glyph
        return Menu {
            // Black & White uses SF Symbols only: their shapes stay crisp in the menu bar.
            if settings.iconStyle.mode == .color {
                Section("Characters") {
                    ForEach(MenuBarIconStyle.characters, id: \.self) { character in
                        Button(character) { glyphs.wrappedValue[status] = .character(character) }
                    }
                }
            }
            Section("Symbols") {
                ForEach(MenuBarIconStyle.monochromeSymbols, id: \.self) { name in
                    Button { glyphs.wrappedValue[status] = .symbol(name) } label: {
                        Label(IconGlyph.symbol(name).title, systemImage: name)
                    }
                }
            }
            Divider()
            Button("Import Image…") { importImage(for: status) }
        } label: {
            switch current {
            case .symbol(let name): Label(current.title, systemImage: name)
            default: Text(current.title)
            }
        }
        .fixedSize()
    }

    private func importImage(for status: ConnectionStatus) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg, .pdf, .png]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileName = try customIcons.importImage(from: url)
            glyphs.wrappedValue[status] = .custom(fileName: fileName)
            importError = nil
        } catch {
            importError = "Netty could not read that image. Use an SVG, PDF or PNG file."
        }
    }
}

/// The icon at its real size on a strip that looks like the menu bar.
private struct IconPreview: View {
    let appearance: IconAppearance
    let customIcons: CustomIconStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(for: appearance, customIcons: customIcons))
            .foregroundStyle(scheme == .dark ? .white : .black)
            .frame(width: 44, height: 24)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.92), in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

private extension ClickAction {
    var title: String {
        switch self {
        case .showPopover: "Show the popover"
        case .showMenu: "Show the quick menu"
        case .runSpeedTest: "Run a speed test"
        case .openSettings: "Open Settings"
        }
    }
}

private extension IconGlyph {
    /// Readable names: `circle.dashed.inset.fill` tells people nothing.
    static let symbolTitles = [
        "circle": "Circle",
        "circle.fill": "Filled circle",
        "circle.slash": "Circle with slash",
        "circle.dotted": "Dotted circle",
        "circle.dashed": "Dashed circle",
        "circle.dashed.inset.fill": "Dashed circle, filled inside",
        "circlebadge": "Badge",
        "circlebadge.fill": "Filled badge",
        "circle.circle": "Circle in a circle",
        "circle.circle.fill": "Filled circle in a circle",
        "circle.and.line.horizontal": "Circle on a line",
    ]

    var title: String {
        switch self {
        case .character(let character): character
        case .symbol(let name): Self.symbolTitles[name] ?? name
        case .custom: "Custom image"
        }
    }
}
