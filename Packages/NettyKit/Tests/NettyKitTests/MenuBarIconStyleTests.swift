import Foundation
import Testing
@testable import NettyKit

@Suite("IconGlyph")
struct IconGlyphTests {
    @Test(arguments: ["○", "●", "◯", "⬤", "◉", "◎", "◌", "◍"])
    func geometricShapesAreNotEmoji(character: String) {
        #expect(!IconGlyph.character(character).isEmoji)
    }

    @Test func radioButtonIsEmoji() {
        #expect(IconGlyph.character("🔘").isEmoji)
    }

    @Test func symbolsAndCustomImagesAreNotEmoji() {
        #expect(!IconGlyph.symbol("circle.fill").isEmoji)
        #expect(!IconGlyph.custom(fileName: "online.png").isEmoji)
    }
}

@Suite("MenuBarIconStyle")
struct MenuBarIconStyleTests {
    @Test func defaultsMatchTheSpec() {
        let style = MenuBarIconStyle.defaults
        #expect(style.mode == .color)
        #expect(style.colorGlyphs == StatusGlyphs(all: .character("●")))
        #expect(style.monochromeGlyphs == StatusGlyphs(online: .symbol("circle.fill"), degraded: .symbol("circle.dashed.inset.fill"),
                                                       offline: .symbol("circle.dotted")))
        #expect(style.size == 14)
    }

    @Test(arguments: [(ConnectionStatus.online, StatusTint.green), (.degraded, .yellow), (.offline, .red)])
    func colorModeTintsOneGlyphByStatus(status: ConnectionStatus, tint: StatusTint) {
        let appearance = MenuBarIconStyle.defaults.appearance(for: status)
        #expect(appearance == IconAppearance(glyph: .character("●"), size: 14, isTemplate: false, tint: tint, opacity: 1))
    }

    @Test(arguments: [(ConnectionStatus.online, "circle.fill"), (.degraded, "circle.dashed.inset.fill"), (.offline, "circle.dotted")])
    func monochromeModeUsesOneTemplateSymbolPerStatus(status: ConnectionStatus, symbol: String) {
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        #expect(style.appearance(for: status)
            == IconAppearance(glyph: .symbol(symbol), size: 14, isTemplate: true, tint: nil, opacity: 1))
    }

    @Test func monochromeSymbolsAreTheChosenEleven() {
        #expect(MenuBarIconStyle.monochromeSymbols == [
            "circle", "circle.fill", "circle.slash", "circle.dotted", "circle.dashed", "circle.dashed.inset.fill",
            "circlebadge", "circlebadge.fill", "circle.circle", "circle.circle.fill", "circle.and.line.horizontal",
        ])
    }

    @Test func charactersSavedForMonochromeFallBackToTheDefaultSymbol() {
        // Black & white offers SF Symbols only; a character chosen before keeps working as the default.
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        style.monochromeGlyphs.offline = .character("◌")
        #expect(style.appearance(for: .offline).glyph == .symbol("circle.dotted"))
    }

    @Test func aChosenMonochromeSymbolIsUsed() {
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        style.monochromeGlyphs.offline = .symbol("circle.slash")
        #expect(style.appearance(for: .offline).glyph == .symbol("circle.slash"))
    }

    @Test func checkingShowsTheOnlineGlyphDimmed() {
        let color = MenuBarIconStyle.defaults.appearance(for: nil)
        #expect(color.glyph == .character("●"))
        #expect(color.tint == .gray)
        #expect(color.opacity == 0.4)
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        #expect(style.appearance(for: nil).opacity == 0.4)
        #expect(style.appearance(for: nil).isTemplate)
    }

    @Test func emojiKeepsItsOwnColorsInColorMode() {
        var style = MenuBarIconStyle.defaults
        style.colorGlyphs = StatusGlyphs(all: .character("🔘"))
        let appearance = style.appearance(for: .online)
        #expect(appearance.glyph == .character("🔘"))
        #expect(appearance.tint == nil)
        #expect(!appearance.isTemplate)
    }

    @Test func emojiFallsBackToTheDefaultGlyphInMonochromeMode() {
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        style.monochromeGlyphs.degraded = .character("🔘")
        #expect(style.appearance(for: .degraded).glyph == .symbol("circle.dashed.inset.fill"))
    }

    @Test func customImagesAreNotTintedInColorModeAndTemplatesInMonochrome() {
        var style = MenuBarIconStyle.defaults
        style.colorGlyphs.offline = .custom(fileName: "down.png")
        style.monochromeGlyphs.offline = .custom(fileName: "down.png")
        #expect(style.appearance(for: .offline).tint == nil)
        #expect(!style.appearance(for: .offline).isTemplate)
        style.mode = .monochrome
        #expect(style.appearance(for: .offline).isTemplate)
        #expect(style.appearance(for: .offline).glyph == .custom(fileName: "down.png"))
    }

    @Test(arguments: [(4.0, 10.0), (10.0, 10.0), (16.0, 16.0), (18.0, 18.0), (30.0, 18.0)])
    func sizeIsClampedToTheMenuBar(size: Double, expected: Double) {
        var style = MenuBarIconStyle.defaults
        style.size = size
        #expect(style.appearance(for: .online).size == expected)
    }

    @Test func survivesEncoding() throws {
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        style.size = 16
        style.monochromeGlyphs.online = .symbol("wifi")
        style.colorGlyphs.offline = .custom(fileName: "down.png")
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(MenuBarIconStyle.self, from: data) == style)
    }
}
