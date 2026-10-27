import Foundation
import Testing
@testable import NettyKit

@Suite("ClickBehavior")
struct ClickBehaviorTests {
    @Test func defaultsOpenThePopoverAndTheQuickMenu() {
        #expect(ClickBehavior.defaults.left == .showPopover)
        #expect(ClickBehavior.defaults.right == .showMenu)
    }

    @Test func swappedClicksAreKept() {
        let behavior = ClickBehavior(left: .showMenu, right: .showPopover)
        #expect(behavior.validated == behavior)
    }

    @Test(arguments: [ClickAction.runSpeedTest, .openSettings])
    func someClickAlwaysReachesQuit(action: ClickAction) {
        // Without the popover or the menu, Quit and Settings would be unreachable.
        let behavior = ClickBehavior(left: action, right: .runSpeedTest)
        #expect(behavior.validated == ClickBehavior(left: action, right: .showMenu))
    }

    @Test func oneClickWithThePopoverIsEnough() {
        let behavior = ClickBehavior(left: .runSpeedTest, right: .showPopover)
        #expect(behavior.validated == behavior)
    }

    @Test func theMenuOffersThePopoverOnlyWhenNoClickOpensIt() {
        #expect(!ClickBehavior.defaults.menuIncludesPopover)
        #expect(ClickBehavior(left: .runSpeedTest, right: .showMenu).menuIncludesPopover)
    }

    @Test func survivesEncoding() throws {
        let behavior = ClickBehavior(left: .openSettings, right: .showPopover)
        let data = try JSONEncoder().encode(behavior)
        #expect(try JSONDecoder().decode(ClickBehavior.self, from: data) == behavior)
    }
}

@Suite("NettySettings clicks")
struct NettySettingsClickTests {
    private func freshDefaults() -> UserDefaults {
        let name = "NettySettingsClickTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func clicksStartWithTheDefaults() {
        #expect(NettySettings(defaults: freshDefaults()).clickBehavior == .defaults)
    }

    @Test func clicksSurviveARelaunchValidated() {
        let defaults = freshDefaults()
        let sut = NettySettings(defaults: defaults)
        sut.clickBehavior = ClickBehavior(left: .runSpeedTest, right: .openSettings)
        #expect(sut.clickBehavior == ClickBehavior(left: .runSpeedTest, right: .showMenu))
        #expect(NettySettings(defaults: defaults).clickBehavior == ClickBehavior(left: .runSpeedTest, right: .showMenu))
    }
}
