import Foundation

/// A part of the popover the user can show, hide and move.
nonisolated public enum PopoverSection: String, Sendable, Codable, CaseIterable {
    /// Status, how long it has lasted, and the Settings button.
    case status
    /// Latency, jitter and packet loss.
    case quality
    /// The last speed test and its button.
    case speed
    /// Wi-Fi name or interface, and VPN.
    case network
}

/// Which popover sections show, in which order.
nonisolated public struct PopoverLayout: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var section: PopoverSection
        public var isVisible: Bool

        public init(section: PopoverSection, isVisible: Bool) {
            self.section = section
            self.isVisible = isVisible
        }
    }

    /// Every section once, in display order, shown or not.
    public private(set) var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public static let defaults = PopoverLayout(
        entries: PopoverSection.allCases.map { Entry(section: $0, isVisible: true) })

    public var visibleSections: [PopoverSection] {
        entries.filter(\.isVisible).map(\.section)
    }

    public func isVisible(_ section: PopoverSection) -> Bool {
        entries.first { $0.section == section }?.isVisible ?? false
    }

    /// Hiding keeps the section's place, so showing it again puts it back there.
    public mutating func setVisible(_ isVisible: Bool, for section: PopoverSection) {
        guard let index = entries.firstIndex(where: { $0.section == section }) else { return }
        entries[index].isVisible = isVisible
    }

    /// Same contract as SwiftUI's `onMove`: `destination` is an offset in the
    /// list before the move. (SwiftUI's `Array.move` is not available here.)
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { entries.indices.contains($0) }.map { entries[$0] }
        let insertAt = destination - source.count(where: { $0 < destination })
        entries = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        entries.insert(contentsOf: moving, at: min(max(insertAt, 0), entries.count))
    }

    /// Each section exactly once: duplicates dropped, sections the stored
    /// layout does not know (added in a later version) appended and shown.
    public var normalized: PopoverLayout {
        var seen = Set<PopoverSection>()
        var entries = self.entries.filter { seen.insert($0.section).inserted }
        entries += PopoverSection.allCases.filter { !seen.contains($0) }.map { Entry(section: $0, isVisible: true) }
        return PopoverLayout(entries: entries)
    }
}
