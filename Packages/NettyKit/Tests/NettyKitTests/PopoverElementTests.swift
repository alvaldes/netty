import Foundation
import Testing
@testable import NettyKit

@Suite("PopoverLayout elements")
struct PopoverElementTests {
    @Test func everyElementBelongsToItsSectionInDisplayOrder() {
        #expect(PopoverSection.status.elements == [.statusDuration])
        #expect(PopoverSection.quality.elements == [.latency, .jitter, .loss])
        #expect(PopoverSection.speed.elements == [.download, .upload, .responsiveness, .speedTestButton])
        #expect(PopoverSection.network.elements == [.interface, .vpn, .localIP, .publicIP])
    }

    @Test func everyElementShowsByDefault() {
        for element in PopoverElement.allCases {
            #expect(PopoverLayout.defaults.isVisible(element))
        }
    }

    @Test func onlyLatency() {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .jitter)
        layout.setVisible(false, for: .loss)
        #expect(layout.isVisible(.latency))
        #expect(!layout.isVisible(.jitter))
        #expect(!layout.isVisible(.loss))
        #expect(layout.visibleSections.contains(.quality))
    }

    @Test func aSectionWithEveryElementHiddenIsLeftOut() {
        var layout = PopoverLayout.defaults
        for element in PopoverSection.network.elements { layout.setVisible(false, for: element) }
        #expect(layout.visibleSections == [.status, .quality, .speed])
    }

    @Test func statusStaysWithoutItsDuration() {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .statusDuration)
        #expect(layout.visibleSections.first == .status)
    }

    @Test func elementsOfAHiddenSectionAreNotVisible() {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .network)
        #expect(!layout.isVisible(.publicIP))
        layout.setVisible(true, for: .network)
        #expect(layout.isVisible(.publicIP))
    }

    @Test func hiddenElementsSurviveReorderingAndEncoding() throws {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .vpn)
        layout.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let decoded = try JSONDecoder().decode(PopoverLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
        #expect(!decoded.isVisible(.vpn))
    }

    @Test func layoutsSavedBeforeElementsStillLoad() throws {
        // Stored by the previous version: no hidden elements yet.
        let json = #"{"entries":[{"section":"speed","isVisible":true},{"section":"status","isVisible":false}]}"#
        let layout = try JSONDecoder().decode(PopoverLayout.self, from: Data(json.utf8)).normalized
        #expect(layout.entries.map(\.section) == [.speed, .status, .quality, .network])
        #expect(layout.isVisible(.download))
        #expect(!layout.isVisible(.statusDuration))
    }
}

@Suite("NettySettings public IP follows the popover")
struct PublicIPFollowsPopoverTests {
    private func freshDefaults() -> UserDefaults {
        let name = "PublicIPFollowsPopoverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func showsPublicIPIsThePopoverElement() {
        let sut = NettySettings(defaults: freshDefaults())
        sut.popoverLayout.setVisible(false, for: .publicIP)
        #expect(!sut.showsPublicIP)
        sut.showsPublicIP = true
        #expect(sut.popoverLayout.isVisible(.publicIP))
    }

    @Test func aHiddenNetworkSectionLooksNothingUp() {
        let sut = NettySettings(defaults: freshDefaults())
        sut.popoverLayout.setVisible(false, for: .network)
        #expect(!sut.showsPublicIP)
    }

    @Test func theOldSwitchOffCarriesOver() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "showsPublicIP")
        let sut = NettySettings(defaults: defaults)
        #expect(!sut.popoverLayout.isVisible(.publicIP))
        #expect(!NettySettings(defaults: defaults).popoverLayout.isVisible(.publicIP))
    }
}
