import Foundation
import Observation

/// The system services the speed tester depends on, replaceable in tests.
nonisolated public struct SpeedTestClient: Sendable {
    /// Runs one test and returns `networkQuality -c` output.
    public var measure: @Sendable () async throws -> Data
    public var loadLast: @Sendable () -> SpeedTestResult?
    public var saveLast: @Sendable (SpeedTestResult) -> Void
    public var sleep: @Sendable (Duration) async throws -> Void
    public var now: @Sendable () -> Date

    public init(
        measure: @escaping @Sendable () async throws -> Data,
        loadLast: @escaping @Sendable () -> SpeedTestResult?,
        saveLast: @escaping @Sendable (SpeedTestResult) -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.measure = measure
        self.loadLast = loadLast
        self.saveLast = saveLast
        self.sleep = sleep
        self.now = now
    }

    private static let lastResultKey = "lastSpeedTest"

    public static let live = SpeedTestClient(
        measure: { try await NetworkQualityCommand.run() },
        loadLast: {
            UserDefaults.standard.data(forKey: lastResultKey)
                .flatMap { try? JSONDecoder().decode(SpeedTestResult.self, from: $0) }
        },
        saveLast: { result in
            if let data = try? JSONEncoder().encode(result) {
                UserDefaults.standard.set(data, forKey: lastResultKey)
            }
        },
        sleep: { try await Task.sleep(for: $0) },
        now: { Date() }
    )
}

/// Measures the connection's capacity on demand and on an optional schedule.
/// A test uses tens to hundreds of MB, so it never runs continuously.
@Observable
public final class SpeedTester {
    public private(set) var lastResult: SpeedTestResult?
    public private(set) var lastError: (any Error)?
    public private(set) var isRunning = false
    public var schedule = SpeedTestSchedule.off
    /// Scheduled tests skip expensive or constrained networks; manual tests always run.
    public var skipsMeteredNetworks = true

    /// How often the schedule checks whether a test is due.
    static let checkInterval: Duration = .seconds(60)

    private let client: SpeedTestClient
    private let conditions: () -> SpeedTestConditions

    public init(client: SpeedTestClient = .live, conditions: @escaping () -> SpeedTestConditions) {
        self.client = client
        self.conditions = conditions
        lastResult = client.loadLast()
    }

    /// Runs a test now, unless one is running or the connection is offline.
    public func run() async {
        guard !isRunning, conditions().isOnline else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let output = try await client.measure()
            let result = try SpeedTestResult(networkQualityOutput: output, measuredAt: client.now())
            lastResult = result
            lastError = nil
            client.saveLast(result)
        } catch {
            lastError = error
        }
    }

    /// Runs scheduled tests until the calling task is cancelled.
    public func runSchedule() async {
        while true {
            if isDue { await run() }
            do { try await client.sleep(Self.checkInterval) } catch { return }
        }
    }

    private var isDue: Bool {
        guard let interval = schedule.interval else { return false }
        let conditions = conditions()
        guard conditions.isOnline, !(conditions.isMetered && skipsMeteredNetworks) else { return false }
        guard let lastResult else { return true }
        return client.now().timeIntervalSince(lastResult.date) >= interval
    }
}
