/// How the connection looks to the user: the menu bar LED.
nonisolated public enum ConnectionStatus: Sendable, Equatable {
    /// Online, good quality (green).
    case online
    /// Online, but latency, jitter or loss crossed a threshold (yellow).
    case degraded
    /// No internet (red), including Wi-Fi without internet or a captive portal.
    case offline
}

/// The result of one probe round.
nonisolated public struct ProbeSample: Sendable, Equatable {
    /// The reachability probe got the expected answer from the internet.
    public var isReachable: Bool
    /// Latency probe round-trip in milliseconds; `nil` when that probe failed.
    public var latency: Double?

    public static func reachable(latency: Double?) -> ProbeSample {
        ProbeSample(isReachable: true, latency: latency)
    }

    public static let unreachable = ProbeSample(isReachable: false, latency: nil)
}

/// User-adjustable thresholds that turn probe samples into a status.
nonisolated public struct QualityRules: Sendable, Equatable, Codable {
    /// Number of recent samples the metrics are computed over.
    public var windowSize = 6
    /// Median latency, in milliseconds, at or above which the connection is degraded.
    public var latencyThreshold = 150.0
    /// Jitter, in milliseconds, at or above which the connection is degraded.
    public var jitterThreshold = 50.0
    /// Share of failed probes in the window (0...1) at or above which the connection is degraded.
    public var lossThreshold = 0.10
    /// Consecutive failed probes before going offline.
    public var failuresToOffline = 3
    /// Consecutive successful probes before coming back online.
    public var successesToOnline = 2
    /// Consecutive evaluations under every threshold before degraded turns back to online.
    public var evaluationsToRecover = 2

    public init() {}

    public static let defaults = QualityRules()
}

/// Connection quality over the current window.
nonisolated public struct QualityMetrics: Sendable, Equatable {
    /// Median latency in milliseconds; `nil` without latency samples.
    public var latency: Double?
    /// Mean absolute difference between consecutive latencies; `nil` with fewer than two.
    public var jitter: Double?
    /// Share of failed probes in the window (0...1).
    public var loss: Double

    public init(latency: Double?, jitter: Double?, loss: Double) {
        self.latency = latency
        self.jitter = jitter
        self.loss = loss
    }

    public static let empty = QualityMetrics(latency: nil, jitter: nil, loss: 0)

    init(samples: [ProbeSample]) {
        guard !samples.isEmpty else {
            self = .empty
            return
        }
        let latencies = samples.compactMap { $0.isReachable ? $0.latency : nil }
        let failures = samples.count(where: { !$0.isReachable })
        loss = Double(failures) / Double(samples.count)
        latency = Self.median(of: latencies)
        jitter = latencies.count < 2
            ? nil
            : zip(latencies, latencies.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(latencies.count - 1)
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    func isDegraded(under rules: QualityRules) -> Bool {
        if let latency, latency >= rules.latencyThreshold { return true }
        if let jitter, jitter >= rules.jitterThreshold { return true }
        return loss >= rules.lossThreshold
    }
}
