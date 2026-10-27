import Foundation
import Synchronization
import Testing
@testable import NettyKit

@Suite("LocalAddress")
struct LocalAddressTests {
    @Test func loopbackHasItsWellKnownAddress() {
        #expect(LocalAddress.ipv4(of: "lo0") == "127.0.0.1")
    }

    @Test func unknownInterfaceHasNoAddress() {
        #expect(LocalAddress.ipv4(of: "nope42") == nil)
    }
}

@Suite("PublicAddress parsing")
struct PublicAddressParsingTests {
    @Test func readsTheIPFromCloudflareTrace() {
        let body = "fl=190f104\nh=1.1.1.1\nip=203.0.113.7\nts=1793133815.000\nloc=MX\nwarp=off\n"
        #expect(PublicAddress.ip(fromTrace: Data(body.utf8)) == "203.0.113.7")
    }

    @Test(arguments: ["", "fl=1\nh=1.1.1.1\n", "ip=\n", "ip=not-an-address\n", "<html>captive portal</html>"])
    func rejectsTracesWithoutAnAddress(body: String) {
        #expect(PublicAddress.ip(fromTrace: Data(body.utf8)) == nil)
    }

    @Test func acceptsIPv6() {
        #expect(PublicAddress.ip(fromTrace: Data("ip=2001:db8::1\n".utf8)) == "2001:db8::1")
    }
}

/// Scripted lookups and clock shared with the client closures.
private final class FakeLookup: Sendable {
    let answers: Mutex<[String?]>
    let count = Mutex(0)
    let clock = Mutex(Date(timeIntervalSince1970: 0))

    init(_ answers: [String?] = []) {
        self.answers = Mutex(answers)
    }

    var client: PublicAddressClient {
        PublicAddressClient(
            fetch: {
                self.count.withLock { $0 += 1 }
                return self.answers.withLock { $0.isEmpty ? "203.0.113.7" : $0.removeFirst() }
            },
            now: { self.clock.withLock { $0 } }
        )
    }

    var lookups: Int { count.withLock { $0 } }
}

private let wifi = NetworkPath(isSatisfied: true, interface: .wifi, isExpensive: false, isConstrained: false, interfaceName: "en0")
private let ethernet = NetworkPath(isSatisfied: true, interface: .ethernet, isExpensive: false, isConstrained: false, interfaceName: "en10")

@Suite("PublicAddress")
struct PublicAddressTests {
    @Test func looksUpWhenUnknown() async {
        let fake = FakeLookup()
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: wifi)
        #expect(sut.address == "203.0.113.7")
        #expect(fake.lookups == 1)
    }

    @Test func keepsAFreshAnswer() async {
        let fake = FakeLookup()
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: wifi)
        fake.clock.withLock { $0 += 299 }
        await sut.refreshIfStale(path: wifi)
        #expect(fake.lookups == 1)
    }

    @Test func looksUpAgainAfterFiveMinutes() async {
        let fake = FakeLookup(["203.0.113.7", "198.51.100.2"])
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: wifi)
        fake.clock.withLock { $0 += 300 }
        await sut.refreshIfStale(path: wifi)
        #expect(sut.address == "198.51.100.2")
    }

    @Test func aNewNetworkForgetsTheOldAddress() async {
        let fake = FakeLookup(["203.0.113.7", "198.51.100.2"])
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: wifi)
        await sut.refreshIfStale(path: ethernet)
        #expect(sut.address == "198.51.100.2")
        #expect(fake.lookups == 2)
    }

    @Test func aFailedLookupShowsNothingAndRetriesNextTime() async {
        let fake = FakeLookup([nil, "203.0.113.7"])
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: wifi)
        #expect(sut.address == nil)
        await sut.refreshIfStale(path: wifi)
        #expect(sut.address == "203.0.113.7")
    }

    @Test func neverLooksUpWithoutANetwork() async {
        let fake = FakeLookup()
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: NetworkPath(isSatisfied: false, interface: .none, isExpensive: false, isConstrained: false))
        await sut.refreshIfStale(path: nil)
        #expect(fake.lookups == 0)
        #expect(sut.address == nil)
    }

    @Test func turnedOffItNeverLooksUpAndForgets() async {
        let fake = FakeLookup()
        let sut = PublicAddress(client: fake.client)
        await sut.refreshIfStale(path: wifi)
        sut.isEnabled = false
        #expect(sut.address == nil)
        fake.clock.withLock { $0 += 1_000 }
        await sut.refreshIfStale(path: wifi)
        #expect(fake.lookups == 1)
    }
}

@Suite("ConnectionMonitor local address")
struct ConnectionMonitorLocalAddressTests {
    @Test func readsTheAddressOfTheInterfaceInUse() async {
        let asked = Mutex<[String]>([])
        let client = ConnectionClient(
            probe: { .reachable(latency: 20) },
            paths: { AsyncStream { $0.finish() } },
            sleep: { _ in },
            now: { .now },
            wifiName: { nil },
            localAddress: { name in asked.withLock { $0.append(name) }; return "192.168.0.103" }
        )
        let sut = ConnectionMonitor(client: client)
        await sut.handle(ethernet)
        #expect(sut.localAddress == "192.168.0.103")
        #expect(asked.withLock { $0 } == ["en10"])
        await sut.handle(NetworkPath(isSatisfied: false, interface: .none, isExpensive: false, isConstrained: false))
        #expect(sut.localAddress == nil)
    }
}

@Suite("NettySettings public IP")
struct NettySettingsPublicIPTests {
    @Test func publicIPIsOnByDefaultAndPersists() {
        let name = "NettySettingsPublicIPTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let sut = NettySettings(defaults: defaults)
        #expect(sut.showsPublicIP)
        sut.showsPublicIP = false
        #expect(!NettySettings(defaults: defaults).showsPublicIP)
    }
}

@Suite("PublicAddress live")
struct PublicAddressLiveTests {
    /// Asks Cloudflare's 1.1.1.1 trace page; run with NETTY_LIVE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NETTY_LIVE"] == "1"))
    func liveLookupReturnsAnAddress() async {
        let address = await PublicAddressClient.live.fetch()
        #expect(address != nil)
    }
}
