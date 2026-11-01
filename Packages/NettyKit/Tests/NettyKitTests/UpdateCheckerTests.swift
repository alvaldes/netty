import Foundation
import Synchronization
import Testing
@testable import NettyKit

/// A throwaway defaults suite per test.
private func freshDefaults() -> UserDefaults {
    let name = "UpdateCheckerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let page = URL(string: "https://github.com/alvaldes/netty/releases/tag/v1.2.0")!

/// A GitHub that answers with `latest`, counts lookups and records notifications.
private final class FakeUpdates: Sendable {
    let latest: Mutex<AppRelease?>
    let now = Mutex(Date(timeIntervalSince1970: 1_000))
    let fetches = Mutex(0)
    let posted = Mutex<[StatusNotification]>([])

    init(latest: AppRelease?) {
        self.latest = Mutex(latest)
    }

    var client: UpdateClient {
        UpdateClient(
            fetchLatest: {
                self.fetches.withLock { $0 += 1 }
                return self.latest.withLock { $0 }
            },
            now: { self.now.withLock { $0 } }
        )
    }

    var notifications: NotificationClient {
        NotificationClient(requestAuthorization: {},
                           post: { notification in self.posted.withLock { $0.append(notification) } })
    }

    func advance(by seconds: TimeInterval) {
        now.withLock { $0 += seconds }
    }

    var fetchCount: Int { fetches.withLock { $0 } }
    var all: [StatusNotification] { posted.withLock { $0 } }
}

@Suite("Version comparison")
struct VersionComparisonTests {
    @Test(arguments: [
        ("1.0.1", "1.0.0"),
        ("1.10.0", "1.9.0"),
        ("v1.1", "1.0.9"),
        ("2.0.0", "1.99.99"),
    ])
    func newer(candidate: String, current: String) {
        #expect(UpdateChecker.isNewer(candidate, than: current))
    }

    @Test(arguments: [
        ("1.0", "1.0.0"),
        ("1.0.0", "1.0.0"),
        ("0.9.0", "1.0.0"),
        ("latest", "1.0.0"),
        ("1.1.0", "?"),
    ])
    func notNewer(candidate: String, current: String) {
        #expect(!UpdateChecker.isNewer(candidate, than: current))
    }
}

@Suite("GitHub release parsing")
struct GitHubReleaseParsingTests {
    @Test func readsTheTagAndPage() {
        let json = #"{"tag_name":"v1.2.0","html_url":"\#(page.absoluteString)","draft":false,"prerelease":false}"#
        #expect(UpdateChecker.release(fromGitHub: Data(json.utf8)) == AppRelease(version: "1.2.0", pageURL: page))
    }

    @Test func readsTheHighlightsFromTheNotes() {
        let notes = "## What's new\n\n- **Update notices** from GitHub\n- Faster [quick check](https://x.dev)\n\n**Full Changelog**: https://x"
        let json = try! JSONSerialization.data(withJSONObject: [
            "tag_name": "v1.2.0", "html_url": page.absoluteString, "body": notes,
        ])
        #expect(UpdateChecker.release(fromGitHub: json)?.highlights
            == ["Update notices from GitHub", "Faster quick check"])
    }

    @Test(arguments: [
        #"{"tag_name":"v1.2.0","html_url":"https://github.com/x","draft":true,"prerelease":false}"#,
        #"{"tag_name":"v1.2.0","html_url":"https://github.com/x","draft":false,"prerelease":true}"#,
        #"{"html_url":"https://github.com/x"}"#,
        #"{"message":"Not Found"}"#,
        "not json",
    ])
    func ignoresAnythingElse(json: String) {
        #expect(UpdateChecker.release(fromGitHub: Data(json.utf8)) == nil)
    }
}

@Suite("Release highlights")
struct ReleaseHighlightsTests {
    @Test func takesTopLevelBulletsWithoutMarkdown() {
        let notes = """
        ## What's new
        - **Bold** and `code`
        * Star bullet
          - Nested detail
        Plain paragraph
        + Plus bullet
        """
        #expect(UpdateChecker.highlights(fromNotes: notes) == ["Bold and code", "Star bullet", "Plus bullet"])
    }

    @Test func dropsGitHubsGeneratedAuthorAndLink() {
        let notes = "- Add update notices by @alvaldes in https://github.com/alvaldes/netty/pull/12"
        #expect(UpdateChecker.highlights(fromNotes: notes) == ["Add update notices"])
    }

    @Test func noBulletsMeansNoHighlights() {
        #expect(UpdateChecker.highlights(fromNotes: "**Full Changelog**: https://x").isEmpty)
    }
}

@Suite("Update check schedule")
struct UpdateCheckScheduleTests {
    @Test func intervals() {
        #expect(UpdateCheckSchedule.off.interval == nil)
        #expect(UpdateCheckSchedule.every6Hours.interval == 21_600)
        #expect(UpdateCheckSchedule.daily.interval == 86_400)
        #expect(UpdateCheckSchedule.weekly.interval == 604_800)
    }
}

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    private let newer = AppRelease(version: "1.2.0", pageURL: page,
                                   highlights: ["Update notices", "Check interval", "Release notes"])

    private func checker(_ fake: FakeUpdates, defaults: UserDefaults, current: String = "1.0.0") -> UpdateChecker {
        UpdateChecker(currentVersion: current, client: fake.client, notifications: fake.notifications,
                      defaults: defaults)
    }

    @Test func notifiesOnceAboutANewerVersion() async {
        let fake = FakeUpdates(latest: newer)
        let sut = checker(fake, defaults: freshDefaults())

        await sut.checkIfDue()

        #expect(sut.available == newer)
        #expect(fake.all == [StatusNotification(title: "Netty 1.2.0 is available",
                                                body: "• Update notices\n• Check interval\n• Release notes",
                                                identifier: "update-available", url: page)])
    }

    @Test func summarizesLongNotes() async {
        let long = AppRelease(version: "1.2.0", pageURL: page, highlights: ["A", "B", "C", "D", "E"])
        let fake = FakeUpdates(latest: long)

        await checker(fake, defaults: freshDefaults()).checkIfDue()

        #expect(fake.all.map(\.body) == ["• A\n• B\n• C\nand 2 more"])
    }

    @Test func withoutNotesItPointsToTheReleasePage() async {
        let fake = FakeUpdates(latest: AppRelease(version: "1.2.0", pageURL: page))

        await checker(fake, defaults: freshDefaults()).checkIfDue()

        #expect(fake.all.map(\.body) == ["Click to see what's new and download it."])
    }

    @Test func doesNotNotifyTheSameVersionAgainAfterARelaunch() async {
        let defaults = freshDefaults()
        let fake = FakeUpdates(latest: newer)
        await checker(fake, defaults: defaults).checkIfDue()

        let relaunched = checker(fake, defaults: defaults)
        await relaunched.checkIfDue()

        #expect(relaunched.available == newer)
        #expect(fake.all.count == 1)
    }

    @Test func notifiesAgainForAnEvenNewerVersion() async {
        let fake = FakeUpdates(latest: newer)
        let sut = checker(fake, defaults: freshDefaults())
        await sut.checkIfDue()

        fake.latest.withLock { $0 = AppRelease(version: "1.3.0", pageURL: page) }
        fake.advance(by: UpdateCheckSchedule.daily.interval!)
        await sut.checkIfDue()

        #expect(fake.all.map(\.title) == ["Netty 1.2.0 is available", "Netty 1.3.0 is available"])
    }

    @Test func staysQuietWhenUpToDate() async {
        let fake = FakeUpdates(latest: AppRelease(version: "1.0.0", pageURL: page))
        let sut = checker(fake, defaults: freshDefaults())

        await sut.checkIfDue()

        #expect(sut.available == nil)
        #expect(!sut.lastCheckFailed)
        #expect(sut.lastCheck != nil)
        #expect(fake.all.isEmpty)
    }

    @Test(arguments: [UpdateCheckSchedule.every6Hours, .daily, .weekly])
    func checksAtMostOncePerInterval(schedule: UpdateCheckSchedule) async {
        let fake = FakeUpdates(latest: newer)
        let sut = checker(fake, defaults: freshDefaults())
        sut.schedule = schedule

        await sut.checkIfDue()
        fake.advance(by: schedule.interval! - 60)
        await sut.checkIfDue()
        #expect(fake.fetchCount == 1)

        fake.advance(by: 60)
        await sut.checkIfDue()
        #expect(fake.fetchCount == 2)
    }

    @Test func doesNothingWhenTurnedOff() async {
        let fake = FakeUpdates(latest: newer)
        let sut = checker(fake, defaults: freshDefaults())
        sut.schedule = .off

        await sut.checkIfDue()

        #expect(fake.fetchCount == 0)
        #expect(sut.available == nil)
        #expect(fake.all.isEmpty)
    }

    @Test func checkNowShowsTheUpdateWithoutNotifying() async {
        let fake = FakeUpdates(latest: newer)
        let sut = checker(fake, defaults: freshDefaults())
        sut.schedule = .off

        await sut.checkNow()

        #expect(sut.available == newer)
        #expect(fake.all.isEmpty)
    }

    @Test func aFailedLookupIsReportedAndKeepsTheLastAnswer() async {
        let fake = FakeUpdates(latest: newer)
        let sut = checker(fake, defaults: freshDefaults())
        await sut.checkNow()

        fake.latest.withLock { $0 = nil }
        await sut.checkNow()

        #expect(sut.lastCheckFailed)
        #expect(sut.available == newer)
    }
}
