import Foundation
import Testing
@testable import NettyKit

private func evaluator(_ rules: QualityRules = .defaults) -> QualityEvaluator {
    QualityEvaluator(rules: rules)
}

private extension QualityEvaluator {
    mutating func record(_ samples: [ProbeSample]) {
        for sample in samples { record(sample) }
    }

    mutating func recordReachable(_ latencies: [Double]) {
        record(latencies.map { .reachable(latency: $0) })
    }
}

@Suite("QualityRules")
struct QualityRulesTests {
    @Test func defaultsMatchTheSpec() {
        let rules = QualityRules.defaults
        #expect(rules.windowSize == 6)
        #expect(rules.latencyThreshold == 150)
        #expect(rules.jitterThreshold == 50)
        #expect(rules.lossThreshold == 0.10)
        #expect(rules.failuresToOffline == 3)
        #expect(rules.successesToOnline == 2)
        #expect(rules.evaluationsToRecover == 2)
    }

    @Test func survivesEncoding() throws {
        var rules = QualityRules.defaults
        rules.latencyThreshold = 300
        rules.failuresToOffline = 5
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(QualityRules.self, from: data) == rules)
    }
}

@Suite("QualityEvaluator")
struct QualityEvaluatorTests {
    @Test func hasNoStatusBeforeTheFirstProbe() {
        #expect(evaluator().status == nil)
    }

    @Test func firstFastProbeIsOnline() {
        var sut = evaluator()
        sut.record(.reachable(latency: 20))
        #expect(sut.status == .online)
    }

    @Test func firstSlowProbeIsDegraded() {
        var sut = evaluator()
        sut.record(.reachable(latency: 400))
        #expect(sut.status == .degraded)
    }

    @Test func goesOfflineOnlyAfterConsecutiveFailures() {
        var sut = evaluator()
        sut.recordReachable([20, 20, 20, 20, 20, 20])
        sut.record([.unreachable, .unreachable])
        #expect(sut.status != .offline)
        sut.record(.unreachable)
        #expect(sut.status == .offline)
    }

    @Test func aSuccessResetsTheFailureCount() {
        var sut = evaluator()
        sut.recordReachable([20])
        sut.record([.unreachable, .unreachable, .reachable(latency: 20), .unreachable, .unreachable])
        #expect(sut.status != .offline)
    }

    @Test func failuresBeforeTheFirstSuccessGoOffline() {
        var sut = evaluator()
        sut.record([.unreachable, .unreachable, .unreachable])
        #expect(sut.status == .offline)
    }

    @Test func unsatisfiedPathIsOfflineImmediately() {
        var sut = evaluator()
        sut.recordReachable([20])
        sut.pathChanged(isSatisfied: false)
        #expect(sut.status == .offline)
    }

    @Test func comesBackOnlineAfterConsecutiveSuccesses() {
        var sut = evaluator()
        sut.pathChanged(isSatisfied: false)
        sut.record(.reachable(latency: 20))
        #expect(sut.status == .offline)
        sut.record(.reachable(latency: 20))
        #expect(sut.status == .online)
    }

    @Test func aFailureWhileOfflineRestartsRecovery() {
        var sut = evaluator()
        sut.pathChanged(isSatisfied: false)
        sut.record([.reachable(latency: 20), .unreachable, .reachable(latency: 20)])
        #expect(sut.status == .offline)
    }

    @Test func outageFailuresDoNotCountAsLossAfterRecovery() {
        var sut = evaluator()
        sut.recordReachable([20])
        sut.record([.unreachable, .unreachable, .unreachable])
        sut.recordReachable([20, 20])
        #expect(sut.status == .online)
        #expect(sut.metrics.loss == 0)
    }

    @Test func medianLatencyAtTheThresholdIsDegraded() {
        var sut = evaluator()
        sut.recordReachable([150, 150, 150])
        #expect(sut.status == .degraded)
        #expect(sut.metrics.latency == 150)
    }

    @Test func medianOfAnEvenWindowAveragesTheMiddleSamples() {
        var sut = evaluator()
        sut.recordReachable([10, 20, 40, 100])
        #expect(sut.metrics.latency == 30)
    }

    @Test func oneSlowSampleDoesNotMoveTheMedian() {
        var sut = evaluator()
        sut.recordReachable([20, 20, 20, 20, 20, 20])
        // Jitter rises with the spike, so keep it from deciding this test.
        sut.rules.jitterThreshold = 1_000
        sut.record(.reachable(latency: 900))
        #expect(sut.status == .online)
    }

    @Test func highJitterIsDegraded() {
        var sut = evaluator()
        sut.recordReachable([20, 90, 20, 90])
        #expect(sut.metrics.jitter == 70)
        #expect(sut.status == .degraded)
    }

    @Test func lossAtTheThresholdIsDegraded() {
        var sut = evaluator()
        sut.recordReachable([20, 20, 20, 20, 20])
        sut.record(.unreachable)
        #expect(sut.metrics.loss == 1.0 / 6.0)
        #expect(sut.status == .degraded)
    }

    @Test func reachableWithoutLatencyIsNotLoss() {
        var sut = evaluator()
        sut.record([.reachable(latency: 20), .reachable(latency: nil), .reachable(latency: 20)])
        #expect(sut.metrics.loss == 0)
        #expect(sut.metrics.latency == 20)
        #expect(sut.status == .online)
    }

    @Test func recoversFromDegradedOnlyAfterConsecutiveCleanEvaluations() {
        var rules = QualityRules.defaults
        rules.windowSize = 2
        var sut = evaluator(rules)
        sut.recordReachable([400, 400])
        #expect(sut.status == .degraded)
        sut.recordReachable([20, 20])
        // The window is clean from here on: first clean evaluation.
        #expect(sut.status == .degraded)
        sut.recordReachable([20])
        #expect(sut.status == .online)
    }

    @Test func oldSamplesLeaveTheWindow() {
        var sut = evaluator()
        sut.recordReachable([400, 400, 400])
        sut.recordReachable([20, 20, 20, 20, 20, 20])
        #expect(sut.metrics == QualityMetrics(latency: 20, jitter: 0, loss: 0))
    }

    @Test func customRulesAreApplied() {
        var rules = QualityRules.defaults
        rules.latencyThreshold = 300
        rules.failuresToOffline = 1
        var sut = evaluator(rules)
        sut.recordReachable([200, 200])
        #expect(sut.status == .online)
        sut.record(.unreachable)
        #expect(sut.status == .offline)
    }

    @Test func networkChangeClearsTheWindowButKeepsTheStatus() {
        var sut = evaluator()
        sut.recordReachable([400, 400])
        sut.pathChanged(isSatisfied: true)
        #expect(sut.status == .degraded)
        #expect(sut.metrics == QualityMetrics(latency: nil, jitter: nil, loss: 0))
    }
}
