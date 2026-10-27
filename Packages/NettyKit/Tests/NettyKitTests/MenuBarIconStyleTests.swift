import Foundation
import Testing
@testable import NettyKit

private let defaultGlyphs = StatusGlyphs(online: .symbol("circle.fill"), degraded: .symbol("circle.dashed"),
                                         offline: .symbol("circle.and.line.horizontal"))

@Suite("MenuBarIconStyle")
struct MenuBarIconStyleTests {
    @Test func defaultsMatchTheSpec() {
        let style = MenuBarIconStyle.defaults
        #expect(style.mode == .color)
        #expect(style.colorGlyphs == defaultGlyphs)
        #expect(style.monochromeGlyphs == defaultGlyphs)
        #expect(style.size == 14)
    }

    @Test func symbolsAreTheChosenEight() {
        #expect(MenuBarIconStyle.symbols == [
            "circle", "circle.fill", "circle.slash", "circle.dotted", "circle.dashed", "circle.dashed.inset.fill",
            "circle.circle", "circle.and.line.horizontal",
        ])
    }

    @Test(arguments: [(ConnectionStatus.online, StatusTint.green, "circle.fill"),
                      (.degraded, .yellow, "circle.dashed"),
                      (.offline, .red, "circle.and.line.horizontal")])
    func colorModeTintsTheSymbolByStatus(status: ConnectionStatus, tint: StatusTint, symbol: String) {
        let appearance = MenuBarIconStyle.defaults.appearance(for: status)
        #expect(appearance == IconAppearance(glyph: .symbol(symbol), size: 14, isTemplate: false, tint: tint, opacity: 1))
    }

    @Test(arguments: [(ConnectionStatus.online, "circle.fill"), (.degraded, "circle.dashed"),
                      (.offline, "circle.and.line.horizontal")])
    func monochromeModeUsesOneTemplateSymbolPerStatus(status: ConnectionStatus, symbol: String) {
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        #expect(style.appearance(for: status)
            == IconAppearance(glyph: .symbol(symbol), size: 14, isTemplate: true, tint: nil, opacity: 1))
    }

    @Test(arguments: [MenuBarIconStyle.Mode.color, .monochrome])
    func charactersSavedBeforeFallBackToTheDefaultSymbol(mode: MenuBarIconStyle.Mode) {
        // Only SF Symbols and imported images are offered now; a saved ● or 🔘 keeps working as the default.
        var style = MenuBarIconStyle.defaults
        style.mode = mode
        style.colorGlyphs = StatusGlyphs(all: .character("🔘"))
        style.monochromeGlyphs = StatusGlyphs(all: .character("◌"))
        #expect(style.appearance(for: .offline).glyph == .symbol("circle.and.line.horizontal"))
        #expect(style.appearance(for: .online).glyph == .symbol("circle.fill"))
    }

    @Test func aChosenSymbolIsUsed() {
        var style = MenuBarIconStyle.defaults
        style.colorGlyphs.offline = .symbol("circle.slash")
        style.monochromeGlyphs.degraded = .symbol("circle.dotted")
        #expect(style.appearance(for: .offline).glyph == .symbol("circle.slash"))
        style.mode = .monochrome
        #expect(style.appearance(for: .degraded).glyph == .symbol("circle.dotted"))
    }

    @Test func checkingShowsTheOnlineSymbolDimmed() {
        let color = MenuBarIconStyle.defaults.appearance(for: nil)
        #expect(color.glyph == .symbol("circle.fill"))
        #expect(color.tint == .gray)
        #expect(color.opacity == 0.4)
        var style = MenuBarIconStyle.defaults
        style.mode = .monochrome
        #expect(style.appearance(for: nil).opacity == 0.4)
        #expect(style.appearance(for: nil).isTemplate)
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
        style.monochromeGlyphs.online = .symbol("circle.circle")
        style.colorGlyphs.offline = .custom(fileName: "down.png")
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(MenuBarIconStyle.self, from: data) == style)
    }

    @Test func stylesSavedWithCharactersStillDecode() throws {
        let saved = #"{"mode":"color","size":14,"colorGlyphs":{"online":{"character":{"_0":"●"}},"degraded":{"character":{"_0":"●"}},"offline":{"character":{"_0":"●"}}},"monochromeGlyphs":{"online":{"character":{"_0":"●"}},"degraded":{"character":{"_0":"◍"}},"offline":{"character":{"_0":"◌"}}}}"#
        let style = try JSONDecoder().decode(MenuBarIconStyle.self, from: Data(saved.utf8))
        #expect(style.appearance(for: .degraded).glyph == .symbol("circle.dashed"))
    }
}
