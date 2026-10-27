import Network
import Synchronization

/// Measures latency as the TCP connect time to well-known anycast hosts. ICMP ping
/// needs raw sockets; a TCP handshake is one round trip and needs no privileges.
nonisolated enum LatencyProbe {
    static let hosts: [NWEndpoint.Host] = ["1.1.1.1", "8.8.8.8"]
    static let port: NWEndpoint.Port = 443
    static let timeout: Duration = .seconds(2)

    /// The fastest round trip in milliseconds, or `nil` when every host failed.
    @concurrent
    static func measure() async -> Double? {
        await withTaskGroup(of: Double?.self) { group in
            for host in hosts {
                group.addTask { await connectTime(to: host) }
            }
            return await group.compactMap { $0 }.reduce(into: [Double]()) { $0.append($1) }.min()
        }
    }

    @concurrent
    private static func connectTime(to host: NWEndpoint.Host) async -> Double? {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        let queue = DispatchQueue(label: "Netty.LatencyProbe")
        let clock = ContinuousClock()
        let start = clock.now
        let finished = Mutex(false)

        let elapsed: Duration? = await withCheckedContinuation { continuation in
            @Sendable func finish(_ value: Duration?) {
                guard finished.withLock({ done in defer { done = true }; return !done }) else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(clock.now - start)
                case .failed, .cancelled: finish(nil)
                case .waiting: finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout.components.seconds * 1000))) { finish(nil) }
        }
        guard let elapsed else { return nil }
        let (seconds, attoseconds) = elapsed.components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
