import Foundation

/// One measurement of the connection's capacity.
nonisolated public struct SpeedTestResult: Sendable, Equatable, Codable {
    /// Download capacity in Mbps.
    public var download: Double
    /// Upload capacity in Mbps.
    public var upload: Double
    /// Round trips per minute under load (Apple's responsiveness metric, RPM).
    public var responsiveness: Double
    /// Data the test used, download plus upload.
    public var bytesTransferred: Int
    public var date: Date

    public init(download: Double, upload: Double, responsiveness: Double, bytesTransferred: Int, date: Date) {
        self.download = download
        self.upload = upload
        self.responsiveness = responsiveness
        self.bytesTransferred = bytesTransferred
        self.date = date
    }

    /// Parses `networkQuality -c` output, whose throughputs are in bits per second.
    init(networkQualityOutput data: Data, measuredAt date: Date) throws {
        struct Output: Decodable {
            var dl_throughput: Double
            var ul_throughput: Double
            var responsiveness: Double
            var dl_bytes_transferred: Int
            var ul_bytes_transferred: Int
        }
        let output = try JSONDecoder().decode(Output.self, from: data)
        self.init(
            download: output.dl_throughput / 1_000_000,
            upload: output.ul_throughput / 1_000_000,
            responsiveness: output.responsiveness,
            bytesTransferred: output.dl_bytes_transferred + output.ul_bytes_transferred,
            date: date
        )
    }
}

/// How often the speed test runs on its own.
nonisolated public enum SpeedTestSchedule: String, Sendable, CaseIterable, Codable {
    case off, hourly, every6Hours, daily

    /// Seconds between scheduled tests; `nil` when off.
    public var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .hourly: 3_600
        case .every6Hours: 21_600
        case .daily: 86_400
        }
    }
}

/// What the speed tester needs to know about the connection right now.
nonisolated public struct SpeedTestConditions: Sendable, Equatable {
    public var isOnline: Bool
    /// Expensive or constrained path, e.g. an iPhone hotspot or Low Data Mode.
    public var isMetered: Bool

    public init(isOnline: Bool, isMetered: Bool) {
        self.isOnline = isOnline
        self.isMetered = isMetered
    }
}
