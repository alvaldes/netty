import Foundation
import Synchronization
import Testing
@testable import NettyKit

nonisolated private let fixture: Data = {
    let url = Bundle.module.url(forResource: "networkQuality", withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}()

private struct MeasureFailed: Error {}

/// Scripted speed tests, clock and storage shared with the client closures.
private final class FakeSpeedTest: Sendable {
    let outputs: Mutex<[Result<Data, any Error>]>
    let measureCount = Mutex(0)
    let saved = Mutex<SpeedTestResult?>(nil)
    let stored: SpeedTestResult?
    let clock = Mutex(Date(timeIntervalSince1970: 1_000_000))
    let allowedSleeps: Int
    let sleepCount = Mutex(0)

    init(outputs: [Result<Data, any Error>] = [], stored: SpeedTestResult? = nil, allowedSleeps: Int = 0) {
        self.outputs = Mutex(outputs)
        self.stored = stored
        self.allowedSleeps = allowedSleeps
    }

    func advance(by seconds: TimeInterval) {
        clock.withLock { $0 += seconds }
    }

    var client: SpeedTestClient {
        SpeedTestClient(
            measure: {
                self.measureCount.withLock { $0 += 1 }
                return try self.outputs.withLock { $0.isEmpty ? .success(fixture) : $0.removeFirst() }.get()
            },
            loadLast: { self.stored },
            saveLast: { result in self.saved.withLock { $0 = result } },
            sleep: { _ in
                let count = self.sleepCount.withLock { $0 += 1; return $0 }
                if count > self.allowedSleeps { throw CancellationError() }
            },
            now: { self.clock.withLock { $0 } }
        )
    }
}

private let online = SpeedTestConditions(isOnline: true, isMetered: false)

@Suite("SpeedTestResult")
struct SpeedTestResultTests {
    @Test func parsesNetworkQualityOutput() throws {
        let date = Date(timeIntervalSince1970: 42)
        let result = try SpeedTestResult(networkQualityOutput: fixture, measuredAt: date)
        #expect(result.download == 9.188107)
        #expect(result.upload == 19.45526)
        #expect(result.responsiveness == 61.11968994140625)
        #expect(result.bytesTransferred == 19_266_517 + 23_855_100)
        #expect(result.date == date)
    }

    @Test func rejectsOutputWithoutThroughput() {
        #expect(throws: (any Error).self) {
            try SpeedTestResult(networkQualityOutput: Data(#"{"error_code": 1}"#.utf8), measuredAt: .now)
        }
    }
}

@Suite("SpeedTestSchedule")
struct SpeedTestScheduleTests {
    @Test func intervals() {
        #expect(SpeedTestSchedule.off.interval == nil)
        #expect(SpeedTestSchedule.hourly.interval == 3_600)
        #expect(SpeedTestSchedule.every6Hours.interval == 21_600)
        #expect(SpeedTestSchedule.daily.interval == 86_400)
    }
}

@Suite("SpeedTester")
struct SpeedTesterTests {
    @Test func runStoresAndSavesTheResult() async {
        let fake = FakeSpeedTest()
        let sut = SpeedTester(client: fake.client, conditions: { online })
        await sut.run()
        #expect(sut.lastResult?.download == 9.188107)
        #expect(sut.lastResult?.date == Date(timeIntervalSince1970: 1_000_000))
        #expect(fake.saved.withLock { $0 } == sut.lastResult)
        #expect(sut.lastError == nil)
        #expect(!sut.isRunning)
    }

    @Test func loadsTheLastSavedResult() {
        let stored = SpeedTestResult(download: 50, upload: 10, responsiveness: 800, bytesTransferred: 1, date: .distantPast)
        let sut = SpeedTester(client: FakeSpeedTest(stored: stored).client, conditions: { online })
        #expect(sut.lastResult == stored)
    }

    @Test func neverRunsWhileOffline() async {
        let fake = FakeSpeedTest()
        let sut = SpeedTester(client: fake.client, conditions: { SpeedTestConditions(isOnline: false, isMetered: false) })
        await sut.run()
        #expect(fake.measureCount.withLock { $0 } == 0)
        #expect(sut.lastResult == nil)
    }

    @Test func aFailedTestKeepsThePreviousResult() async {
        let fake = FakeSpeedTest(outputs: [.success(fixture), .failure(MeasureFailed())])
        let sut = SpeedTester(client: fake.client, conditions: { online })
        await sut.run()
        let previous = sut.lastResult
        await sut.run()
        #expect(sut.lastResult == previous)
        #expect(sut.lastError != nil)
    }

    @Test func aSuccessfulTestClearsThePreviousError() async {
        let fake = FakeSpeedTest(outputs: [.failure(MeasureFailed()), .success(fixture)])
        let sut = SpeedTester(client: fake.client, conditions: { online })
        await sut.run()
        await sut.run()
        #expect(sut.lastError == nil)
    }

    @Test func scheduleOffNeverRuns() async {
        let fake = FakeSpeedTest(allowedSleeps: 3)
        let sut = SpeedTester(client: fake.client, conditions: { online })
        await sut.runSchedule()
        #expect(fake.measureCount.withLock { $0 } == 0)
    }

    @Test func scheduleRunsWhenNoResultExists() async {
        let fake = FakeSpeedTest()
        let sut = SpeedTester(client: fake.client, conditions: { online })
        sut.schedule = .hourly
        await sut.runSchedule()
        #expect(fake.measureCount.withLock { $0 } == 1)
    }

    @Test func scheduleWaitsUntilTheIntervalHasPassed() async {
        let fake = FakeSpeedTest()
        let recent = SpeedTestResult(download: 1, upload: 1, responsiveness: 1, bytesTransferred: 1,
                                     date: fake.clock.withLock { $0 }.addingTimeInterval(-3_000))
        let sut = SpeedTester(client: FakeSpeedTest(stored: recent).client, conditions: { online })
        sut.schedule = .hourly
        await sut.runSchedule()
        #expect(sut.lastResult == recent)
    }

    @Test func scheduleRunsOnceTheIntervalHasPassed() async {
        let fake = FakeSpeedTest(stored: SpeedTestResult(download: 1, upload: 1, responsiveness: 1, bytesTransferred: 1,
                                                         date: Date(timeIntervalSince1970: 1_000_000 - 3_600)))
        let sut = SpeedTester(client: fake.client, conditions: { online })
        sut.schedule = .hourly
        await sut.runSchedule()
        #expect(fake.measureCount.withLock { $0 } == 1)
    }

    @Test func scheduleSkipsMeteredNetworksByDefault() async {
        let fake = FakeSpeedTest()
        let sut = SpeedTester(client: fake.client, conditions: { SpeedTestConditions(isOnline: true, isMetered: true) })
        sut.schedule = .hourly
        await sut.runSchedule()
        #expect(fake.measureCount.withLock { $0 } == 0)
    }

    @Test func scheduleRunsOnMeteredNetworksWhenAllowed() async {
        let fake = FakeSpeedTest()
        let sut = SpeedTester(client: fake.client, conditions: { SpeedTestConditions(isOnline: true, isMetered: true) })
        sut.schedule = .hourly
        sut.skipsMeteredNetworks = false
        await sut.runSchedule()
        #expect(fake.measureCount.withLock { $0 } == 1)
    }

    @Test func manualRunIgnoresTheMeteredSetting() async {
        let fake = FakeSpeedTest()
        let sut = SpeedTester(client: fake.client, conditions: { SpeedTestConditions(isOnline: true, isMetered: true) })
        await sut.run()
        #expect(fake.measureCount.withLock { $0 } == 1)
    }

    @Test func scheduleKeepsCheckingAfterEachWait() async {
        let fake = FakeSpeedTest(allowedSleeps: 2)
        let sut = SpeedTester(client: fake.client, conditions: { online })
        sut.schedule = .hourly
        await sut.runSchedule()
        // Runs once at start; the next checks are within the hour.
        #expect(fake.measureCount.withLock { $0 } == 1)
        #expect(fake.sleepCount.withLock { $0 } == 3)
    }
}

@Suite("NetworkQualityCommand")
struct NetworkQualityCommandTests {
    /// Runs a real speed test (about 20 s and tens of MB); run with NETTY_LIVE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NETTY_LIVE"] == "1"))
    func liveRunReturnsAParsableResult() async throws {
        let output = try await NetworkQualityCommand.run()
        let result = try SpeedTestResult(networkQualityOutput: output, measuredAt: .now)
        #expect(result.download > 0)
        #expect(result.upload > 0)
    }
}
