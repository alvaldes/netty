/// What a click on the menu bar icon does.
nonisolated public enum ClickAction: String, Sendable, Codable, CaseIterable {
    case showPopover, showMenu, runSpeedTest, openSettings

    /// Opens something that leads to Settings and Quit.
    var reachesQuit: Bool { self == .showPopover || self == .showMenu }
}

/// The actions of the left and the right click on the menu bar icon.
nonisolated public struct ClickBehavior: Sendable, Equatable, Codable {
    public var left: ClickAction
    public var right: ClickAction

    public init(left: ClickAction, right: ClickAction) {
        self.left = left
        self.right = right
    }

    public static let defaults = ClickBehavior(left: .showPopover, right: .showMenu)

    /// One click must open the popover or the menu: otherwise Settings and Quit
    /// are out of reach. The right click then opens the menu.
    public var validated: ClickBehavior {
        left.reachesQuit || right.reachesQuit ? self : ClickBehavior(left: left, right: .showMenu)
    }

    /// The quick menu offers the popover when no click opens it.
    public var menuIncludesPopover: Bool {
        left != .showPopover && right != .showPopover
    }
}
