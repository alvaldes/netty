import Foundation
import Observation

/// The system services the monitor depends on, replaceable in tests.
nonisolated public struct ConnectionClient: Sendable {
    public var probe: @Sendable () async -> ProbeSample
    public var paths: @Sendable () -> AsyncStream<NetworkPath>
    public var sleep: @Sendable (Duration) async throws -> Void
    public var now: @Sendable () -> Date
    /// The Wi-Fi network name; `nil` without Location access.
    public var wifiName: @Sendable () -> String?
    /// The Mac's IPv4 address on an interface.
    public var localAddress: @Sendable (String) -> String?

    public init(
        probe: @escaping @Sendable () async -> ProbeSample,
        paths: @escaping @Sendable () -> AsyncStream<NetworkPath>,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        now: @escaping @Sendable () -> Date,
        wifiName: @escaping @Sendable () -> String?,
        localAddress: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.probe = probe
        self.paths = paths
        self.sleep = sleep
        self.now = now
        self.wifiName = wifiName
        self.localAddress = localAddress
    }

    public static let live = ConnectionClient(
        probe: {
            async let reachable = ReachabilityProbe.check()
            async let latency = LatencyProbe.measure()
            return await reachable ? .reachable(latency: latency) : .unreachable
        },
        paths: { NetworkPath.updates() },
        sleep: { try await Task.sleep(for: $0) },
        now: { Date() },
        wifiName: { WiFiNetwork.currentName() },
        localAddress: { LocalAddress.ipv4(of: $0) }
    )
}

/// Probes the connection on an interval and on every network change, and
/// publishes the resulting status for the menu bar and the popover.
@Observable
public final class ConnectionMonitor {
    public private(set) var status: ConnectionStatus?
    public private(set) var metrics = QualityMetrics.empty
    public private(set) var path: NetworkPath?
    /// The Wi-Fi network name, when on Wi-Fi and Location access is granted.
    public private(set) var wifiName: String?
    /// The Mac's address on the network in use.
    public private(set) var localAddress: String?
    /// When the current status started.
    public private(set) var statusSince: Date?
    public var probeInterval: Duration
    /// Called after the status changes, with the previous status and when it changed.
    public var onStatusChange: ((ConnectionStatus?, ConnectionStatus?, Date) -> Void)?
    public var rules: QualityRules {
        get { evaluator.rules }
        set { evaluator.rules = newValue }
    }

    private var evaluator: QualityEvaluator
    private let client: ConnectionClient
    /// The probe running now; a second caller waits for it instead of probing twice.
    private var inFlight: Task<ProbeSample, Never>?

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

    /// Probes now. When a probe is already running, waits for its answer instead.
    public func recheck() async {
        _ = await probe()
    }

    /// For a click on the icon: an answer now, not after the interval. One probe
    /// when it agrees with the status shown; when it does not, the probes the
    /// rules need to confirm the change (3 failures, 2 successes) run at once,
    /// side by side, instead of one per interval.
    public func quickCheck() async {
        let before = status
        let first = await probe()
        let confirms = before == .offline ? !first.isReachable : first.isReachable
        guard !confirms else { return }
        let needed = (before == .offline ? rules.successesToOnline : rules.failuresToOffline) - 1
        guard needed > 0 else { return }
        let client = client
        let samples = await withTaskGroup(of: ProbeSample.self) { group in
            for _ in 0..<needed {
                group.addTask { await client.probe() }
            }
            var samples: [ProbeSample] = []
            for await sample in group {
                samples.append(sample)
            }
            return samples
        }
        for sample in samples {
            evaluator.record(sample)
        }
        publish()
    }

    /// Probes and records the answer, or returns the answer of the probe already running.
    private func probe() async -> ProbeSample {
        if let inFlight { return await inFlight.value }
        let client = client
        let task = Task { await client.probe() }
        inFlight = task
        let sample = await task.value
        inFlight = nil
        evaluator.record(sample)
        publish()
        return sample
    }

    func handle(_ newPath: NetworkPath) async {
        path = newPath
        evaluator.pathChanged(isSatisfied: newPath.isSatisfied)
        refreshNetworkInfo()
        publish()
        if newPath.isSatisfied {
            await recheck()
        }
    }

    /// Re-reads the Wi-Fi name, e.g. after Location access changes.
    public func refreshNetworkInfo() {
        wifiName = path.map { $0.isSatisfied && $0.interface == .wifi } == true ? client.wifiName() : nil
        localAddress = path?.interfaceName.flatMap(client.localAddress)
    }

    private func publish() {
        if evaluator.status != status {
            let old = status
            status = evaluator.status
            statusSince = client.now()
            onStatusChange?(old, status, client.now())
        }
        metrics = evaluator.metrics
    }
}
