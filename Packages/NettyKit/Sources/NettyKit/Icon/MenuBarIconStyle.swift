/// What the menu bar icon draws for one status.
nonisolated public enum IconGlyph: Sendable, Equatable, Codable {
    /// A text character such as `●` or `◍`.
    case character(String)
    /// An SF Symbol name.
    case symbol(String)
    /// An image the user imported, by its file name in Netty's icon folder.
    case custom(fileName: String)

    /// Emoji draw in their own colors: they can be neither tinted nor used as a template.
    public var isEmoji: Bool {
        guard case .character(let text) = self else { return false }
        return text.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }
}

/// One glyph per status.
nonisolated public struct StatusGlyphs: Sendable, Equatable, Codable {
    public var online: IconGlyph
    public var degraded: IconGlyph
    public var offline: IconGlyph

    public init(online: IconGlyph, degraded: IconGlyph, offline: IconGlyph) {
        self.online = online
        self.degraded = degraded
        self.offline = offline
    }

    public init(all glyph: IconGlyph) {
        self.init(online: glyph, degraded: glyph, offline: glyph)
    }

    /// The glyph for a status; while the first check runs, the online glyph.
    public subscript(status: ConnectionStatus?) -> IconGlyph {
        get {
            switch status {
            case .online, nil: online
            case .degraded: degraded
            case .offline: offline
            }
        }
        set {
            switch status {
            case .online, nil: online = newValue
            case .degraded: degraded = newValue
            case .offline: offline = newValue
            }
        }
    }
}

/// The status colors of Color mode.
nonisolated public enum StatusTint: Sendable, Equatable {
    case green, yellow, red, gray
}

/// Everything needed to draw the icon for one status.
nonisolated public struct IconAppearance: Sendable, Equatable {
    public var glyph: IconGlyph
    /// Point size.
    public var size: Double
    /// Drawn as a template image: macOS colors it to match the menu bar.
    public var isTemplate: Bool
    /// Color to paint the glyph with; `nil` keeps the glyph's own colors.
    public var tint: StatusTint?
    public var opacity: Double

    public init(glyph: IconGlyph, size: Double, isTemplate: Bool, tint: StatusTint?, opacity: Double) {
        self.glyph = glyph
        self.size = size
        self.isTemplate = isTemplate
        self.tint = tint
        self.opacity = opacity
    }
}

/// How the menu bar icon looks, set by the user.
nonisolated public struct MenuBarIconStyle: Sendable, Equatable, Codable {
    public enum Mode: String, Sendable, Codable, CaseIterable {
        /// One glyph tinted green, yellow or red.
        case color
        /// Black and white, matching the menu bar: the glyph's shape carries the status.
        case monochrome
    }

    public static let sizeRange = 10.0...18.0
    public static let characters = ["○", "●", "◯", "⬤", "◉", "◎", "◌", "◍", "🔘"]

    public var mode = Mode.color
    /// Used in Color mode.
    public var colorGlyphs = StatusGlyphs(all: .character("●"))
    /// Used in Monochrome mode, where each status needs its own shape.
    public var monochromeGlyphs = Self.defaultMonochromeGlyphs
    /// Point size, kept within `sizeRange`.
    public var size = 14.0

    public init() {}

    public static let defaults = MenuBarIconStyle()

    static let defaultMonochromeGlyphs = StatusGlyphs(
        online: .character("●"), degraded: .character("◍"), offline: .character("◌"))

    public func appearance(for status: ConnectionStatus?) -> IconAppearance {
        let size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        // The first check has not decided yet.
        let opacity = status == nil ? 0.4 : 1
        switch mode {
        case .color:
            let glyph = colorGlyphs[status]
            let isTintable = if case .custom = glyph { false } else { !glyph.isEmoji }
            return IconAppearance(glyph: glyph, size: size, isTemplate: false,
                                  tint: isTintable ? status.tint : nil, opacity: opacity)
        case .monochrome:
            var glyph = monochromeGlyphs[status]
            if glyph.isEmoji { glyph = Self.defaultMonochromeGlyphs[status] }
            return IconAppearance(glyph: glyph, size: size, isTemplate: true, tint: nil, opacity: opacity)
        }
    }
}

private extension Optional where Wrapped == ConnectionStatus {
    nonisolated var tint: StatusTint {
        switch self {
        case .online: .green
        case .degraded: .yellow
        case .offline: .red
        case nil: .gray
        }
    }
}
