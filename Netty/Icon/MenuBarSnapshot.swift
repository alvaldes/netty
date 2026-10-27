#if DEBUG
import AppKit
import NettyKit

/// Debug only: captures the real menu bar icon as drawn by the status bar, to
/// review it without looking at the screen. Run with
/// `NETTY_RENDER_MENUBAR=<directory>`; `NETTY_ICON_MODE=monochrome` switches the mode.
enum MenuBarSnapshot {
    static var requestedStyle: MenuBarIconStyle? {
        guard ProcessInfo.processInfo.environment["NETTY_RENDER_MENUBAR"] != nil else { return nil }
        var style = MenuBarIconStyle.defaults
        if let mode = ProcessInfo.processInfo.environment["NETTY_ICON_MODE"].flatMap(MenuBarIconStyle.Mode.init) {
            style.mode = mode
        }
        return style
    }

    /// Renders every kind of glyph, tinted and as a template, side by side on a
    /// light and a dark bar. Run with `NETTY_RENDER_ICONS=<directory>`; set
    /// `NETTY_ICON_CUSTOM=<svg|pdf|png>` to include an imported image.
    static func renderGlyphsIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["NETTY_RENDER_ICONS"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = CustomIconStore(folder: output.appending(path: "icons", directoryHint: .isDirectory))
        var glyphs: [IconGlyph] = [.character("●"), .character("◍"), .character("◌"), .character("🔘")]
            + MenuBarIconStyle.monochromeSymbols.map(IconGlyph.symbol)
        if let path = ProcessInfo.processInfo.environment["NETTY_ICON_CUSTOM"],
           let fileName = try? store.importImage(from: URL(fileURLWithPath: path)) {
            glyphs.append(.custom(fileName: fileName))
        }
        let statuses: [ConnectionStatus?] = [.online, .degraded, .offline, nil]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let cell = 26.0
                let sheet = NSImage(size: NSSize(width: cell * Double(statuses.count * 2 + 1),
                                                 height: cell * Double(glyphs.count + 1)), flipped: true) { rect in
                    (name == "dark" ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                    rect.fill()
                    for (row, glyph) in glyphs.enumerated() {
                        for (column, mode) in [MenuBarIconStyle.Mode.color, .monochrome].enumerated() {
                            for (offset, status) in statuses.enumerated() {
                                var style = MenuBarIconStyle.defaults
                                style.mode = mode
                                style.size = row == 0 ? 18 : 14
                                style.colorGlyphs = StatusGlyphs(all: glyph)
                                style.monochromeGlyphs[status] = glyph
                                let icon = MenuBarIconRenderer.image(for: style.appearance(for: status), customIcons: store)
                                let x = cell * Double(column * (statuses.count + 1) + offset)
                                // Templates draw black; the menu bar inverts them on a dark bar.
                                if icon.isTemplate, name == "dark" {
                                    let white = NSImage(size: icon.size, flipped: false) { iconRect in
                                        icon.draw(in: iconRect)
                                        NSColor.white.set()
                                        iconRect.fill(using: .sourceAtop)
                                        return true
                                    }
                                    white.draw(in: NSRect(x: x + 2, y: cell * Double(row) + 2, width: 22, height: 22))
                                } else {
                                    icon.draw(in: NSRect(x: x + 2, y: cell * Double(row) + 2, width: 22, height: 22))
                                }
                            }
                        }
                    }
                    return true
                }
                if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appending(path: "glyphs-\(name).png"))
                }
            }
        }
        exit(0)
    }

    static func captureIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["NETTY_RENDER_MENUBAR"] else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Wait for the first probe to set a status.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let mode = ProcessInfo.processInfo.environment["NETTY_ICON_MODE"] ?? "color"
            for (index, window) in NSApp.windows.enumerated()
            where String(describing: type(of: window)).contains("StatusBar") {
                guard let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?
                    .write(to: output.appending(path: "menubar-\(mode)-\(index).png"))
            }
            exit(0)
        }
    }
}
#endif
