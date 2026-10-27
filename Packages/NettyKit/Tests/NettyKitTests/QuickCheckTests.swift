import Foundation
import Synchronization
import Testing
@testable import NettyKit

/// Scripted probes; sleeping is an error: a quick check never waits for the interval.
private final class ScriptedProbes: Sendable {
    let samples: Mutex<[ProbeSample]>
    let count = Mutex(0)
    let slept = Mutex(false)

    init(_ samples: [ProbeSample]) {
        self.samples = Mutex(samples)
    }

    var client: ConnectionClient {
        ConnectionClient(
            probe: {
                self.count.withLock { $0 += 1 }
                return self.samples.withLock { $0.isEmpty ? .reachable(latency: 20) : $0.removeFirst() }
            },
            paths: { AsyncStream { $0.finish() } },
            sleep: { _ in self.slept.withLock { $0 = true } },
            now: { Date(timeIntervalSince1970: 0) },
            wifiName: { nil }
        )
    }

    var probes: Int { count.withLock { $0 } }
}

private let good = ProbeSample.reachable(latency: 20)
private let bad = ProbeSample.unreachable

@Suite("ConnectionMonitor quick check")
struct QuickCheckTests {
    /// A monitor already in `status`, with the scripted probes queued after the setup.
    private func monitor(online: Bool, then samples: [ProbeSample]) async -> (ConnectionMonitor, ScriptedProbes) {
        let setup: [ProbeSample] = online ? [good] : [bad, bad, bad]
        let probes = ScriptedProbes(setup + samples)
        let sut = ConnectionMonitor(client: probes.client)
        for _ in setup { await sut.recheck() }
        probes.count.withLock { $0 = 0 }
        return (sut, probes)
    }

    @Test func aConfirmingAnswerStopsAtOneProbe() async {
        let (sut, probes) = await monitor(online: true, then: [good])
        await sut.quickCheck()
        #expect(probes.probes == 1)
        #expect(sut.status == .online)
    }

    @Test func aDropIsConfirmedRightAway() async {
        let (sut, probes) = await monitor(online: true, then: [bad, bad, bad])
        await sut.quickCheck()
        #expect(sut.status == .offline)
        #expect(probes.probes == 3)
        #expect(!probes.slept.withLock { $0 })
    }

    @Test func aBlipThatRecoversStaysOnline() async {
        let (sut, _) = await monitor(online: true, then: [bad, good, good])
        await sut.quickCheck()
        #expect(sut.status != .offline)
    }

    @Test func comingBackIsConfirmedRightAway() async {
        let (sut, probes) = await monitor(online: false, then: [good, good])
        await sut.quickCheck()
        #expect(sut.status == .online)
        #expect(probes.probes == 2)
    }

    @Test func stillOfflineStopsAtOneProbe() async {
        let (sut, probes) = await monitor(online: false, then: [bad])
        await sut.quickCheck()
        #expect(sut.status == .offline)
        #expect(probes.probes == 1)
    }

    @Test func theFirstCheckDecidesAtOnce() async {
        let probes = ScriptedProbes([good])
        let sut = ConnectionMonitor(client: probes.client)
        await sut.quickCheck()
        #expect(sut.status == .online)
        #expect(probes.probes == 1)
    }

    @Test func followsTheRules() async {
        var rules = QualityRules.defaults
        rules.failuresToOffline = 5
        let probes = ScriptedProbes([good, bad, bad, bad, bad, bad])
        let sut = ConnectionMonitor(client: probes.client, rules: rules)
        await sut.recheck()
        await sut.quickCheck()
        #expect(sut.status == .offline)
    }
}
