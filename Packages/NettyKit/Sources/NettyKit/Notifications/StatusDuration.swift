import Foundation

/// How long a status has lasted, as people read it: "45 secs", "3 min", "2 hrs, 14 min".
nonisolated public enum StatusDuration {
    public static func text(seconds: TimeInterval, locale: Locale = .current) -> String {
        let seconds = max(0, seconds.rounded())
        // Seconds only matter during the first minute.
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(seconds)
            .formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2).locale(locale))
    }
}
