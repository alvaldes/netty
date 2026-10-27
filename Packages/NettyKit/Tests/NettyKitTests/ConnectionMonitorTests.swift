import Foundation
import Synchronization
import Testing
@testable import NettyKit

/// Scripted probes, path updates and clock shared with the client closures.
private final class FakeNetwork: Sendable {
    let samples: Mutex<[ProbeSample]>
    let probeCount = Mutex(0)
    let allowedSleeps: Int
    let sleepCount = Mutex(0)
    let clock = Mutex(Date(timeIntervalSince1970: 0))
    let wifiName: Mutex<String?>

    init(samples: [ProbeSample] = [], allowedSleeps: Int = 0, wifiName: String? = nil) {
        self.samples = Mutex(samples)
        self.allowedSleeps = allowedSleeps
        self.wifiName = Mutex(wifiName)
    }

    func advance(by seconds: TimeInterval) {
        clock.withLock { $0 += seconds }
    }

    func client(paths: [NetworkPath] = []) -> ConnectionClient {
        ConnectionClient(
            probe: {
                self.probeCount.withLock { $0 += 1 }
                return self.samples.withLock { $0.isEmpty ? .reachable(latency: 20) : $0.removeFirst() }
            },
            paths: {
                AsyncStream { continuation in
                    for path in paths { continuation.yield(path) }
                    continuation.finish()
                }
            },
            sleep: { _ in
                let count = self.sleepCount.withLock { $0 += 1; return $0 }
                if count > self.allowedSleeps { throw CancellationError() }
            },
            now: { self.clock.withLock { $0 } },
            wifiName: { self.wifiName.withLock { $0 } }
        )
    }
}

private let wifi = NetworkPath(isSatisfied: true, interface: .wifi, isExpensive: false, isConstrained: false)
private let noNetwork = NetworkPath(isSatisfied: false, interface: .none, isExpensive: false, isConstrained: false)

@Suite("ConnectionMonitor")
struct ConnectionMonitorTests {
    @Test func recheckProbesAndUpdatesStatusAndMetrics() async {
        let network = FakeNetwork(samples: [.reachable(latency: 30)])
        let sut = ConnectionMonitor(client: network.client())
        await sut.recheck()
        #expect(network.probeCount.withLock { $0 } == 1)
        #expect(sut.status == .online)
        #expect(sut.metrics.latency == 30)
    }

    @Test func statusSinceMovesOnlyWhenTheStatusChanges() async {
        let network = FakeNetwork(samples: [.reachable(latency: 20), .reachable(latency: 20), .reachable(latency: 900)])
        let sut = ConnectionMonitor(client: network.client())
        await sut.recheck()
        let since = sut.statusSince
        #expect(since == Date(timeIntervalSince1970: 0))
        network.advance(by: 10)
        await sut.recheck()
        #expect(sut.statusSince == since)
        network.advance(by: 10)
        await sut.recheck()
        #expect(sut.status == .degraded)
        #expect(sut.statusSince == Date(timeIntervalSince1970: 20))
    }

    @Test func unsatisfiedPathGoesOfflineWithoutProbing() async {
        let network = FakeNetwork()
        let sut = ConnectionMonitor(client: network.client())
        await sut.handle(noNetwork)
        #expect(sut.status == .offline)
        #expect(sut.path == noNetwork)
        #expect(network.probeCount.withLock { $0 } == 0)
    }

    @Test func satisfiedPathProbesImmediately() async {
        let network = FakeNetwork()
        let sut = ConnectionMonitor(client: network.client())
        await sut.handle(wifi)
        #expect(network.probeCount.withLock { $0 } == 1)
        #expect(sut.status == .online)
        #expect(sut.path == wifi)
    }

    @Test func runProbesOnEveryIntervalUntilCancelled() async {
        let network = FakeNetwork(allowedSleeps: 2)
        let sut = ConnectionMonitor(client: network.client())
        await sut.run()
        #expect(network.probeCount.withLock { $0 } == 3)
    }

    @Test func runAppliesPathUpdates() async {
        let network = FakeNetwork()
        let sut = ConnectionMonitor(client: network.client(paths: [noNetwork]))
        await sut.run()
        #expect(sut.path == noNetwork)
    }

    @Test func changedRulesApplyToTheNextProbe() async {
        let network = FakeNetwork(samples: [.reachable(latency: 200)])
        let sut = ConnectionMonitor(client: network.client())
        var rules = QualityRules.defaults
        rules.latencyThreshold = 300
        sut.rules = rules
        await sut.recheck()
        #expect(sut.status == .online)
    }
}

@Suite("ReachabilityProbe")
struct ReachabilityProbeTests {
    @Test func appleSuccessPageIsReachable() {
        let body = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
        #expect(ReachabilityProbe.isAppleSuccess(statusCode: 200, body: Data(body.utf8)))
    }

    @Test(arguments: [
        (200, "<html><body>Please sign in to Hotel Wi-Fi</body></html>"),
        (302, ""),
        (500, "Success"),
    ])
    func captivePortalOrErrorIsNotReachable(statusCode: Int, body: String) {
        #expect(!ReachabilityProbe.isAppleSuccess(statusCode: statusCode, body: Data(body.utf8)))
    }

    /// Hits the real network; run with NETTY_LIVE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NETTY_LIVE"] == "1"))
    func liveProbeReachesTheInternet() async {
        let sample = await ConnectionClient.live.probe()
        #expect(sample.isReachable)
        #expect(sample.latency != nil)
    }
}

@Suite("NetworkPath")
struct NetworkPathTests {
    @Test(arguments: ["utun0", "utun4", "ipsec0", "ppp0"])
    func tunnelInterfacesAreVPN(name: String) {
        #expect(NetworkPath.isTunnel(interfaceName: name))
    }

    @Test(arguments: ["en0", "en10", "bridge0", "awdl0", "lo0"])
    func physicalInterfacesAreNotVPN(name: String) {
        #expect(!NetworkPath.isTunnel(interfaceName: name))
    }
}

@Suite("ConnectionMonitor network info")
struct ConnectionMonitorNetworkInfoTests {
    @Test func wifiPathReadsTheNetworkName() async {
        let sut = ConnectionMonitor(client: FakeNetwork(wifiName: "Home").client())
        await sut.handle(wifi)
        #expect(sut.wifiName == "Home")
    }

    @Test func otherPathsHaveNoNetworkName() async {
        let network = FakeNetwork(wifiName: "Home")
        let sut = ConnectionMonitor(client: network.client())
        await sut.handle(wifi)
        await sut.handle(NetworkPath(isSatisfied: true, interface: .ethernet, isExpensive: false, isConstrained: false))
        #expect(sut.wifiName == nil)
        await sut.handle(wifi)
        await sut.handle(noNetwork)
        #expect(sut.wifiName == nil)
    }

    @Test func refreshRereadsTheNetworkName() async {
        // Without Location access the name is nil; granting it later must show it.
        let network = FakeNetwork(wifiName: nil)
        let sut = ConnectionMonitor(client: network.client())
        await sut.handle(wifi)
        #expect(sut.wifiName == nil)
        network.wifiName.withLock { $0 = "Home" }
        sut.refreshNetworkInfo()
        #expect(sut.wifiName == "Home")
    }
}
