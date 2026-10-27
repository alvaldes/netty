import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
///
/// Launch at login is stored by the system (`SMAppService`) and permissions by
/// macOS, so they are not duplicated here.
@Observable
public final class NettySettings {
    public static let probeIntervals = [5, 10, 30, 60]

    public var qualityRules: QualityRules {
        didSet {
            let validated = qualityRules.validated
            if validated != qualityRules { qualityRules = validated }
            store(qualityRules, forKey: Key.qualityRules)
        }
    }

    /// Seconds between probes; one of `probeIntervals`.
    public var probeInterval: Int {
        didSet {
            guard Self.probeIntervals.contains(probeInterval) else {
                probeInterval = oldValue
                return
            }
            defaults.set(probeInterval, forKey: Key.probeInterval)
            onChange?()
        }
    }

    public var speedTestSchedule: SpeedTestSchedule {
        didSet {
            defaults.set(speedTestSchedule.rawValue, forKey: Key.speedTestSchedule)
            onChange?()
        }
    }

    /// Scheduled speed tests skip expensive or constrained networks.
    public var skipsMeteredNetworks: Bool {
        didSet {
            defaults.set(skipsMeteredNetworks, forKey: Key.skipsMeteredNetworks)
            onChange?()
        }
    }

    public var notifiesWhenOffline: Bool {
        didSet {
            defaults.set(notifiesWhenOffline, forKey: Key.notifiesWhenOffline)
            onChange?()
        }
    }

    public var notifiesWhenBackOnline: Bool {
        didSet {
            defaults.set(notifiesWhenBackOnline, forKey: Key.notifiesWhenBackOnline)
            onChange?()
        }
    }

    public var iconStyle: MenuBarIconStyle {
        didSet { store(iconStyle, forKey: Key.iconStyle) }
    }

    public var clickBehavior: ClickBehavior {
        didSet {
            let validated = clickBehavior.validated
            if validated != clickBehavior { clickBehavior = validated }
            store(clickBehavior, forKey: Key.clickBehavior)
        }
    }

    public var popoverLayout: PopoverLayout {
        didSet { store(popoverLayout, forKey: Key.popoverLayout) }
    }

    /// The welcome window asks for permissions once, on the first launch.
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Called after any setting changes, to apply it to the running services.
    public var onChange: (() -> Void)?

    private let defaults: UserDefaults

    private enum Key {
        static let qualityRules = "qualityRules"
        static let probeInterval = "probeInterval"
        static let speedTestSchedule = "speedTestSchedule"
        static let skipsMeteredNetworks = "skipsMeteredNetworks"
        static let notifiesWhenOffline = "notifiesWhenOffline"
        static let notifiesWhenBackOnline = "notifiesWhenBackOnline"
        static let iconStyle = "iconStyle"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let clickBehavior = "clickBehavior"
        static let popoverLayout = "popoverLayout"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        qualityRules = Self.decoded(QualityRules.self, forKey: Key.qualityRules, in: defaults)?.validated ?? .defaults
        let interval = defaults.object(forKey: Key.probeInterval) as? Int ?? 10
        probeInterval = Self.probeIntervals.contains(interval) ? interval : 10
        speedTestSchedule = defaults.string(forKey: Key.speedTestSchedule).flatMap(SpeedTestSchedule.init) ?? .off
        skipsMeteredNetworks = defaults.object(forKey: Key.skipsMeteredNetworks) as? Bool ?? true
        notifiesWhenOffline = defaults.object(forKey: Key.notifiesWhenOffline) as? Bool ?? true
        notifiesWhenBackOnline = defaults.object(forKey: Key.notifiesWhenBackOnline) as? Bool ?? true
        iconStyle = Self.decoded(MenuBarIconStyle.self, forKey: Key.iconStyle, in: defaults) ?? .defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        popoverLayout = Self.decoded(PopoverLayout.self, forKey: Key.popoverLayout, in: defaults)?.normalized ?? .defaults
        clickBehavior = Self.decoded(ClickBehavior.self, forKey: Key.clickBehavior, in: defaults)?.validated ?? .defaults
    }

    public func resetQualityRules() {
        qualityRules = .defaults
    }

    public func resetPopoverLayout() {
        popoverLayout = .defaults
    }

    private func store(_ value: some Encodable, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
        onChange?()
    }

    private static func decoded<T: Decodable>(_ type: T.Type, forKey key: String, in defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
