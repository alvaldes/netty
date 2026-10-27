import AppKit
import NettyKit

/// Draws the menu bar icon for an `IconAppearance`.
enum MenuBarIconRenderer {
    static func image(for appearance: IconAppearance, customIcons: CustomIconStore = CustomIconStore()) -> NSImage {
        let side = appearance.size + 4
        // Resolved up front: the drawing handler runs again on every redraw.
        let customImage: NSImage? = if case .custom(let fileName) = appearance.glyph {
            customIcons.image(named: fileName)
        } else {
            nil
        }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // One layer, composited at the end: opacity applies to the whole icon,
            // not to each stroke (a template fill would otherwise leave color behind).
            let context = NSGraphicsContext.current?.cgContext
            context?.setAlpha(appearance.opacity)
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { context?.endTransparencyLayer() }
            // Templates only use alpha; macOS colors them to match the menu bar.
            let color = appearance.isTemplate ? NSColor.black : appearance.tint.map(nsColor) ?? .labelColor
            switch appearance.glyph {
            case .character(let text):
                drawCharacter(text, size: appearance.size, color: color, in: rect)
            case .symbol(let name):
                drawSymbol(name, size: appearance.size, color: color, in: rect)
            case .custom:
                guard let customImage else { return true }
                customImage.draw(in: rect.insetBy(dx: 2, dy: 2), from: .zero, operation: .sourceOver, fraction: 1)
                if appearance.isTemplate {
                    color.set()
                    rect.fill(using: .sourceAtop)
                }
            }
            return true
        }
        image.isTemplate = appearance.isTemplate
        image.accessibilityDescription = "Netty"
        return image
    }

    /// Share of the icon size a character's ink fills.
    static let characterInkScale = 0.7

    private static func drawCharacter(_ text: String, size: Double, color: NSColor, in rect: NSRect) {
        func string(fontSize: Double) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color])
        }
        func ink(_ string: NSAttributedString) -> NSRect {
            string.boundingRect(with: rect.size, options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
        }
        // Glyphs differ a lot in size within a font (◌ is far smaller than ●):
        // scale each so its ink fills the same box.
        let measured = ink(string(fontSize: size))
        let largest = max(measured.width, measured.height)
        let fontSize = largest > 0 ? size * (size * characterInkScale / largest) : size
        let scaled = string(fontSize: fontSize)
        let bounds = ink(scaled)
        // Center the ink, not the line box, so every glyph sits at the same height.
        scaled.draw(at: NSPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY))
    }

    private static func drawSymbol(_ name: String, size: Double, color: NSColor, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let origin = NSPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func nsColor(_ tint: StatusTint) -> NSColor {
        switch tint {
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .red: .systemRed
        case .gray: .systemGray
        }
    }
}
