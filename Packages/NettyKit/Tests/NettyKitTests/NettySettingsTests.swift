import Foundation
import Testing
@testable import NettyKit

/// A throwaway defaults suite per test.
private func freshDefaults() -> UserDefaults {
    let name = "NettySettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("QualityRules validation")
struct QualityRulesValidationTests {
    @Test func defaultsAreAlreadyValid() {
        #expect(QualityRules.defaults.validated == .defaults)
    }

    @Test func countsAreAtLeastOne() {
        var rules = QualityRules.defaults
        rules.windowSize = 0
        rules.failuresToOffline = 0
        rules.successesToOnline = -2
        rules.evaluationsToRecover = 0
        let validated = rules.validated
        #expect(validated.windowSize == 1)
        #expect(validated.failuresToOffline == 1)
        #expect(validated.successesToOnline == 1)
        #expect(validated.evaluationsToRecover == 1)
    }

    @Test func thresholdsStayInRange() {
        var rules = QualityRules.defaults
        rules.latencyThreshold = 0
        rules.jitterThreshold = -5
        rules.lossThreshold = 3
        let validated = rules.validated
        #expect(validated.latencyThreshold == 1)
        #expect(validated.jitterThreshold == 1)
        #expect(validated.lossThreshold == 1)
    }

    @Test func zeroFailuresToOfflineWouldOtherwiseBreakTheEvaluator() {
        var rules = QualityRules.defaults
        rules.failuresToOffline = 0
        var sut = QualityEvaluator(rules: rules.validated)
        sut.record(.reachable(latency: 20))
        #expect(sut.status == .online)
    }
}

@Suite("NettySettings")
struct NettySettingsTests {
    @Test func startsWithTheDefaults() {
        let sut = NettySettings(defaults: freshDefaults())
        #expect(sut.qualityRules == .defaults)
        #expect(sut.probeInterval == 10)
        #expect(sut.speedTestSchedule == .off)
        #expect(sut.skipsMeteredNetworks)
        #expect(sut.notifiesWhenOffline)
        #expect(sut.notifiesWhenBackOnline)
        #expect(sut.iconStyle == .defaults)
    }

    @Test func everySettingSurvivesARelaunch() {
        let defaults = freshDefaults()
        let sut = NettySettings(defaults: defaults)
        var rules = QualityRules.defaults
        rules.latencyThreshold = 250
        sut.qualityRules = rules
        sut.probeInterval = 30
        sut.speedTestSchedule = .daily
        sut.skipsMeteredNetworks = false
        sut.notifiesWhenOffline = false
        sut.notifiesWhenBackOnline = false
        var icon = MenuBarIconStyle.defaults
        icon.mode = .monochrome
        icon.size = 16
        sut.iconStyle = icon

        let relaunched = NettySettings(defaults: defaults)
        #expect(relaunched.qualityRules == rules)
        #expect(relaunched.probeInterval == 30)
        #expect(relaunched.speedTestSchedule == .daily)
        #expect(!relaunched.skipsMeteredNetworks)
        #expect(!relaunched.notifiesWhenOffline)
        #expect(!relaunched.notifiesWhenBackOnline)
        #expect(relaunched.iconStyle == icon)
    }

    @Test func invalidRulesAreStoredValidated() {
        let defaults = freshDefaults()
        let sut = NettySettings(defaults: defaults)
        var rules = QualityRules.defaults
        rules.failuresToOffline = 0
        sut.qualityRules = rules
        #expect(sut.qualityRules.failuresToOffline == 1)
        #expect(NettySettings(defaults: defaults).qualityRules.failuresToOffline == 1)
    }

    @Test func probeIntervalIsOneOfTheOffered() {
        let defaults = freshDefaults()
        let sut = NettySettings(defaults: defaults)
        sut.probeInterval = 7
        #expect(sut.probeInterval == 10)
        #expect(NettySettings.probeIntervals == [5, 10, 30, 60])
    }

    @Test func unreadableStoredValuesFallBackToDefaults() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "qualityRules")
        defaults.set("weekly", forKey: "speedTestSchedule")
        defaults.set(Data("{}".utf8), forKey: "iconStyle")
        let sut = NettySettings(defaults: defaults)
        #expect(sut.qualityRules == .defaults)
        #expect(sut.speedTestSchedule == .off)
        #expect(sut.iconStyle == .defaults)
    }

    @Test func resetRestoresTheDefaultRules() {
        let defaults = freshDefaults()
        let sut = NettySettings(defaults: defaults)
        var rules = QualityRules.defaults
        rules.windowSize = 12
        sut.qualityRules = rules
        sut.resetQualityRules()
        #expect(sut.qualityRules == .defaults)
        #expect(NettySettings(defaults: defaults).qualityRules == .defaults)
    }

    @Test func reportsEachChange() {
        let sut = NettySettings(defaults: freshDefaults())
        var changes = 0
        sut.onChange = { changes += 1 }
        sut.probeInterval = 30
        sut.notifiesWhenOffline = false
        #expect(changes == 2)
    }
}
