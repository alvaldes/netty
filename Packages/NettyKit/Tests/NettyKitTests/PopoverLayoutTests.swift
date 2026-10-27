import Foundation
import Testing
@testable import NettyKit

@Suite("PopoverLayout")
struct PopoverLayoutTests {
    @Test func defaultsShowEverySectionInTheDesignOrder() {
        #expect(PopoverLayout.defaults.visibleSections == [.status, .quality, .speed, .network])
    }

    @Test func hiddenSectionsAreLeftOut() {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .speed)
        #expect(layout.visibleSections == [.status, .quality, .network])
        #expect(!layout.isVisible(.speed))
        layout.setVisible(true, for: .speed)
        #expect(layout.visibleSections == [.status, .quality, .speed, .network])
    }

    @Test func sectionsCanBeReordered() {
        var layout = PopoverLayout.defaults
        // Drag Speed (index 2) to the top.
        layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(layout.visibleSections == [.speed, .status, .quality, .network])
        // Drag it to the bottom.
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(layout.visibleSections == [.status, .quality, .network, .speed])
    }

    @Test func aHiddenSectionKeepsItsPlace() {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .quality)
        layout.setVisible(true, for: .quality)
        #expect(layout.entries.map(\.section) == [.status, .quality, .speed, .network])
    }

    @Test func storedLayoutsAreNormalized() {
        // Duplicates dropped, missing sections added at the end, shown.
        let stored = PopoverLayout(entries: [
            .init(section: .network, isVisible: false),
            .init(section: .network, isVisible: true),
            .init(section: .status, isVisible: true),
        ])
        #expect(stored.normalized.entries == [
            .init(section: .network, isVisible: false),
            .init(section: .status, isVisible: true),
            .init(section: .quality, isVisible: true),
            .init(section: .speed, isVisible: true),
        ])
    }

    @Test func survivesEncoding() throws {
        var layout = PopoverLayout.defaults
        layout.setVisible(false, for: .network)
        layout.move(fromOffsets: IndexSet(integer: 1), toOffset: 4)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(PopoverLayout.self, from: data) == layout)
    }
}

@Suite("NettySettings popover layout")
struct NettySettingsPopoverLayoutTests {
    private func freshDefaults() -> UserDefaults {
        let name = "NettySettingsPopoverLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func layoutSurvivesARelaunch() {
        let defaults = freshDefaults()
        let sut = NettySettings(defaults: defaults)
        #expect(sut.popoverLayout == .defaults)
        sut.popoverLayout.setVisible(false, for: .quality)
        sut.popoverLayout.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let relaunched = NettySettings(defaults: defaults)
        #expect(relaunched.popoverLayout == sut.popoverLayout)
        #expect(relaunched.popoverLayout.visibleSections == [.network, .status, .speed])
    }

    @Test func resetRestoresTheDefaultLayout() {
        let sut = NettySettings(defaults: freshDefaults())
        sut.popoverLayout.setVisible(false, for: .status)
        sut.resetPopoverLayout()
        #expect(sut.popoverLayout == .defaults)
    }
}
