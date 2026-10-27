import Foundation
import Observation

/// The system services the monitor depends on, replaceable in tests.
nonisolated public struct ConnectionClient: Sendable {
    public var probe: @Sendable () async -> ProbeSample
    public var paths: @Sendable () -> AsyncStream<NetworkPath>
    public var sleep: @Sendable (Duration) async throws -> Void
    public var now: @Sendable () -> Date

    public init(
        probe: @escaping @Sendable () async -> ProbeSample,
        paths: @escaping @Sendable () -> AsyncStream<NetworkPath>,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.probe = probe
        self.paths = paths
        self.sleep = sleep
        self.now = now
    }

    public static let live = ConnectionClient(
        probe: {
            async let reachable = ReachabilityProbe.check()
            async let latency = LatencyProbe.measure()
            return await reachable ? .reachable(latency: latency) : .unreachable
        },
        paths: { NetworkPath.updates() },
        sleep: { try await Task.sleep(for: $0) },
        now: { Date() }
    )
}

/// Probes the connection on an interval and on every network change, and
/// publishes the resulting status for the menu bar and the popover.
@Observable
public final class ConnectionMonitor {
    public private(set) var status: ConnectionStatus?
    public private(set) var metrics = QualityMetrics.empty
    public private(set) var path: NetworkPath?
    /// When the current status started.
    public private(set) var statusSince: Date?
    public var probeInterval: Duration
    public var rules: QualityRules {
        get { evaluator.rules }
        set { evaluator.rules = newValue }
    }

    private var evaluator: QualityEvaluator
    private let client: ConnectionClient
    private var isProbing = false

    public init(client: ConnectionClient = .live, rules: QualityRules = .defaults, probeInterval: Duration = .seconds(10)) {
        self.client = client
        self.evaluator = QualityEvaluator(rules: rules)
        self.probeInterval = probeInterval
    }

    /// Runs until the calling task is cancelled.
    public func run() async {
        await withTaskGroup { group in
            group.addTask {
                for await path in self.client.paths() {
                    await self.handle(path)
                }
            }
            group.addTask {
                while true {
                    await self.recheck()
                    do { try await self.client.sleep(self.probeInterval) } catch { return }
                }
            }
        }
    }

    /// Probes now. Skipped when a probe is already running.
    public func recheck() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }
        let sample = await client.probe()
        evaluator.record(sample)
        publish()
    }

    func handle(_ newPath: NetworkPath) async {
        path = newPath
        evaluator.pathChanged(isSatisfied: newPath.isSatisfied)
        publish()
        if newPath.isSatisfied {
            await recheck()
        }
    }

    private func publish() {
        if evaluator.status != status {
            status = evaluator.status
            statusSince = client.now()
        }
        metrics = evaluator.metrics
    }
}
