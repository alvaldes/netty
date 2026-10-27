import Foundation
import Synchronization
import Testing
@testable import NettyKit

/// Records posted notifications.
private final class FakeNotifications: Sendable {
    let posted = Mutex<[StatusNotification]>([])

    var client: NotificationClient {
        NotificationClient(
            requestAuthorization: {},
            post: { notification in self.posted.withLock { $0.append(notification) } }
        )
    }

    var all: [StatusNotification] { posted.withLock { $0 } }
}

private let english = Locale(identifier: "en_US")
private let start = Date(timeIntervalSince1970: 1_000)

@Suite("StatusDuration")
struct StatusDurationTests {
    @Test(arguments: [
        (45.0, "45 sec"),
        (59.0, "59 sec"),
        (60.0, "1 min"),
        (181.0, "3 min"),
        (8_040.0, "2 hr, 14 min"),
    ])
    func formats(seconds: Double, expected: String) {
        #expect(StatusDuration.text(seconds: seconds, locale: english) == expected)
    }
}

@Suite("ConnectionNotifier")
struct ConnectionNotifierTests {
    private func notifier(_ fake: FakeNotifications) -> ConnectionNotifier {
        ConnectionNotifier(client: fake.client, locale: english)
    }

    @Test func losingTheConnectionNotifies() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.statusChanged(from: .online, to: .offline, at: start)
        #expect(fake.all == [StatusNotification(title: "Connection lost", body: "Netty can't reach the internet.")])
    }

    @Test func degradedToOfflineNotifies() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.statusChanged(from: .degraded, to: .offline, at: start)
        #expect(fake.all.map(\.title) == ["Connection lost"])
    }

    @Test(arguments: [ConnectionStatus.online, .degraded])
    func comingBackNotifiesWithTheDowntime(status: ConnectionStatus) {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.statusChanged(from: .online, to: .offline, at: start)
        sut.statusChanged(from: .offline, to: status, at: start.addingTimeInterval(181))
        #expect(fake.all.last == StatusNotification(title: "Back online", body: "You were offline for 3 min."))
    }

    @Test func qualityChangesNeverNotify() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.statusChanged(from: .online, to: .degraded, at: start)
        sut.statusChanged(from: .degraded, to: .online, at: start)
        #expect(fake.all.isEmpty)
    }

    @Test func theFirstStatusAtLaunchDoesNotNotify() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.statusChanged(from: nil, to: .online, at: start)
        sut.statusChanged(from: nil, to: .offline, at: start)
        #expect(fake.all.isEmpty)
    }

    @Test func comingBackAfterLaunchingOfflineNotifies() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.statusChanged(from: nil, to: .offline, at: start)
        sut.statusChanged(from: .offline, to: .online, at: start.addingTimeInterval(45))
        #expect(fake.all == [StatusNotification(title: "Back online", body: "You were offline for 45 sec.")])
    }

    @Test func offlineNotificationsCanBeTurnedOff() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.notifiesWhenOffline = false
        sut.statusChanged(from: .online, to: .offline, at: start)
        sut.statusChanged(from: .offline, to: .online, at: start.addingTimeInterval(60))
        #expect(fake.all.map(\.title) == ["Back online"])
    }

    @Test func backOnlineNotificationsCanBeTurnedOff() {
        let fake = FakeNotifications()
        let sut = notifier(fake)
        sut.notifiesWhenBackOnline = false
        sut.statusChanged(from: .online, to: .offline, at: start)
        sut.statusChanged(from: .offline, to: .online, at: start.addingTimeInterval(60))
        #expect(fake.all.map(\.title) == ["Connection lost"])
    }
}

@Suite("ConnectionMonitor status changes")
struct ConnectionMonitorStatusChangeTests {
    @Test func reportsEachChangeOnce() async {
        let client = ConnectionClient(
            probe: { .reachable(latency: 20) },
            paths: { AsyncStream { $0.finish() } },
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 7) },
            wifiName: { nil }
        )
        let sut = ConnectionMonitor(client: client)
        struct Change: Equatable {
            var old: ConnectionStatus?
            var new: ConnectionStatus?
            var date: Date
        }
        let changes = Mutex<[Change]>([])
        sut.onStatusChange = { old, new, date in
            changes.withLock { $0.append(Change(old: old, new: new, date: date)) }
        }
        await sut.recheck()
        await sut.recheck()
        await sut.handle(NetworkPath(isSatisfied: false, interface: .none, isExpensive: false, isConstrained: false))
        let date = Date(timeIntervalSince1970: 7)
        #expect(changes.withLock { $0 } == [Change(old: nil, new: .online, date: date),
                                            Change(old: .online, new: .offline, date: date)])
    }
}
