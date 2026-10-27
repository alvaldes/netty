import Synchronization
import Testing
@testable import NettyKit

/// Fake location authorization shared with the client closures.
private final class FakeLocation: Sendable {
    let status: Mutex<LocationPermission.Status>
    let grantsOnRequest: Bool
    let requestCount = Mutex(0)
    let settingsOpenCount = Mutex(0)

    init(status: LocationPermission.Status, grantsOnRequest: Bool = true) {
        self.status = Mutex(status)
        self.grantsOnRequest = grantsOnRequest
    }

    func client(changes: AsyncStream<Void> = AsyncStream { $0.finish() }) -> LocationClient {
        LocationClient(
            status: { self.status.withLock { $0 } },
            request: {
                self.requestCount.withLock { $0 += 1 }
                self.status.withLock { $0 = self.grantsOnRequest ? .granted : .denied }
            },
            openSystemSettings: { self.settingsOpenCount.withLock { $0 += 1 } },
            changes: { changes }
        )
    }
}

@Suite("LocationPermission")
struct LocationPermissionTests {
    @Test(arguments: [LocationPermission.Status.notDetermined, .granted, .denied])
    func readsTheInitialStatus(status: LocationPermission.Status) {
        #expect(LocationPermission(client: FakeLocation(status: status).client()).status == status)
    }

    @Test func requestAsksTheSystemWhenUndecided() {
        let fake = FakeLocation(status: .notDetermined)
        let sut = LocationPermission(client: fake.client())
        sut.request()
        #expect(fake.requestCount.withLock { $0 } == 1)
        #expect(fake.settingsOpenCount.withLock { $0 } == 0)
    }

    @Test func requestOpensSystemSettingsWhenDenied() {
        // macOS shows its prompt only once; after a denial only System Settings can grant it.
        let fake = FakeLocation(status: .denied)
        let sut = LocationPermission(client: fake.client())
        sut.request()
        #expect(fake.requestCount.withLock { $0 } == 0)
        #expect(fake.settingsOpenCount.withLock { $0 } == 1)
    }

    @Test func requestDoesNothingWhenGranted() {
        let fake = FakeLocation(status: .granted)
        let sut = LocationPermission(client: fake.client())
        sut.request()
        #expect(fake.requestCount.withLock { $0 } == 0)
        #expect(fake.settingsOpenCount.withLock { $0 } == 0)
    }

    @Test func monitorFollowsChangesAndReportsThem() async {
        let fake = FakeLocation(status: .notDetermined)
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let sut = LocationPermission(client: fake.client(changes: changes))
        let reported = Mutex<[LocationPermission.Status]>([])
        sut.onChange = { status in reported.withLock { $0.append(status) } }
        fake.status.withLock { $0 = .granted }
        continuation.yield()
        continuation.finish()
        await sut.monitor()
        #expect(sut.status == .granted)
        #expect(reported.withLock { $0 } == [.granted])
    }
}
