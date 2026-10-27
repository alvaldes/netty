import Foundation

/// A part of the popover the user can show, hide and move.
nonisolated public enum PopoverSection: String, Sendable, Codable, CaseIterable {
    /// Status, how long it has lasted, and the Settings button.
    case status
    /// Latency, jitter and packet loss.
    case quality
    /// The last speed test and its button.
    case speed
    /// Wi-Fi name or interface, VPN, and the IP addresses.
    case network

    /// The parts of this section that can be hidden one by one, in display order.
    public var elements: [PopoverElement] {
        PopoverElement.allCases.filter { $0.section == self }
    }
}

/// One part of a popover section, shown or hidden on its own.
nonisolated public enum PopoverElement: String, Sendable, Codable, CaseIterable {
    /// "for 2 hr, 14 min" under the status.
    case statusDuration
    case latency, jitter, loss
    case download, upload, responsiveness, speedTestButton
    /// Wi-Fi name or the interface type.
    case interface, vpn, localIP, publicIP

    public var section: PopoverSection {
        switch self {
        case .statusDuration: .status
        case .latency, .jitter, .loss: .quality
        case .download, .upload, .responsiveness, .speedTestButton: .speed
        case .interface, .vpn, .localIP, .publicIP: .network
        }
    }
}

/// Which popover sections show, in which order.
nonisolated public struct PopoverLayout: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var section: PopoverSection
        public var isVisible: Bool
        /// Elements of the section the user switched off.
        public var hiddenElements: Set<PopoverElement>

        public init(section: PopoverSection, isVisible: Bool, hiddenElements: Set<PopoverElement> = []) {
            self.section = section
            self.isVisible = isVisible
            self.hiddenElements = hiddenElements
        }

        // Layouts saved before elements existed have no `hiddenElements`.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            section = try container.decode(PopoverSection.self, forKey: .section)
            isVisible = try container.decode(Bool.self, forKey: .isVisible)
            hiddenElements = try container.decodeIfPresent(Set<PopoverElement>.self, forKey: .hiddenElements) ?? []
        }
    }

    /// Every section once, in display order, shown or not.
    public private(set) var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public static let defaults = PopoverLayout(
        entries: PopoverSection.allCases.map { Entry(section: $0, isVisible: true) })

    /// Shown sections with something to show. Status always has its title.
    public var visibleSections: [PopoverSection] {
        entries.filter { entry in
            entry.isVisible && (entry.section == .status || entry.section.elements.contains { !entry.hiddenElements.contains($0) })
        }
        .map(\.section)
    }

    /// Shown: its section is on and it is not switched off.
    public func isVisible(_ element: PopoverElement) -> Bool {
        guard let entry = entries.first(where: { $0.section == element.section }) else { return false }
        return entry.isVisible && !entry.hiddenElements.contains(element)
    }

    public mutating func setVisible(_ isVisible: Bool, for element: PopoverElement) {
        guard let index = entries.firstIndex(where: { $0.section == element.section }) else { return }
        if isVisible {
            entries[index].hiddenElements.remove(element)
        } else {
            entries[index].hiddenElements.insert(element)
        }
    }

    /// Switched on in its section, whether or not the section shows.
    public func isSwitchedOn(_ element: PopoverElement) -> Bool {
        entries.first { $0.section == element.section }.map { !$0.hiddenElements.contains(element) } ?? false
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
