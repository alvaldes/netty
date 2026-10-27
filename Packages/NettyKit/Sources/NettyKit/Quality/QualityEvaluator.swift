/// Turns probe samples and path changes into a connection status, with hysteresis
/// so the LED does not flicker on a single bad probe.
nonisolated public struct QualityEvaluator: Sendable {
    /// `nil` until the first probe or path change decides it.
    public private(set) var status: ConnectionStatus?
    public var rules: QualityRules
    public var metrics: QualityMetrics { QualityMetrics(samples: window) }

    private var window: [ProbeSample] = []
    private var consecutiveFailures = 0
    private var consecutiveSuccesses = 0
    private var cleanEvaluations = 0

    public init(rules: QualityRules = .defaults) {
        self.rules = rules
    }

    public mutating func record(_ sample: ProbeSample) {
        if sample.isReachable {
            consecutiveFailures = 0
            consecutiveSuccesses += 1
        } else {
            consecutiveSuccesses = 0
            consecutiveFailures += 1
        }

        if status == .offline {
            // Recovery only looks at the probes since the outage, so its failures are not loss.
            if sample.isReachable { append(sample) } else { window.removeAll() }
            if consecutiveSuccesses >= rules.successesToOnline {
                status = metrics.isDegraded(under: rules) ? .degraded : .online
                cleanEvaluations = 0
            }
            return
        }

        if consecutiveFailures >= rules.failuresToOffline {
            goOffline()
            return
        }

        append(sample)
        // Before the first success there is nothing to judge quality on.
        guard status != nil || sample.isReachable else { return }
        evaluate()
    }

    /// Call when the system network path changes. A new path is a new network,
    /// so its quality starts from an empty window.
    public mutating func pathChanged(isSatisfied: Bool) {
        guard isSatisfied else {
            goOffline()
            return
        }
        window.removeAll()
        cleanEvaluations = 0
    }

    private mutating func append(_ sample: ProbeSample) {
        window.append(sample)
        if window.count > rules.windowSize {
            window.removeFirst(window.count - rules.windowSize)
        }
    }

    private mutating func goOffline() {
        status = .offline
        window.removeAll()
        consecutiveSuccesses = 0
        cleanEvaluations = 0
    }

    private mutating func evaluate() {
        if metrics.isDegraded(under: rules) {
            status = .degraded
            cleanEvaluations = 0
        } else if status == .degraded {
            cleanEvaluations += 1
            if cleanEvaluations >= rules.evaluationsToRecover {
                status = .online
                cleanEvaluations = 0
            }
        } else {
            status = .online
        }
    }
}
