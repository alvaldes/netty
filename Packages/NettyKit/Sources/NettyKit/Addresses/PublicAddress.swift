import Darwin
import Foundation
import Observation

/// The system services the public address depends on, replaceable in tests.
nonisolated public struct PublicAddressClient: Sendable {
    /// The public IP as the internet sees it; `nil` when the lookup failed.
    public var fetch: @Sendable () async -> String?
    public var now: @Sendable () -> Date

    public init(fetch: @escaping @Sendable () async -> String?, now: @escaping @Sendable () -> Date) {
        self.fetch = fetch
        self.now = now
    }

    /// Cloudflare's trace page on 1.1.1.1: the host Netty already measures latency
    /// against, so no new party learns anything. An IP literal, so no DNS lookup;
    /// HTTPS, so nobody on the way can change the answer.
    static let traceURL = URL(string: "https://1.1.1.1/cdn-cgi/trace")!

    public static let live = PublicAddressClient(
        fetch: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            guard let (data, response) = try? await session.data(from: traceURL),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return PublicAddress.ip(fromTrace: data)
        },
        now: { Date() }
    )
}

/// The public IP, looked up only when the popover shows it: on a new network or
/// once it is five minutes old. No lookups in the background.
@Observable
public final class PublicAddress {
    public private(set) var address: String?
    /// Off: no lookups at all.
    public var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            address = nil
            lookedUp = nil
        }
    }

    static let maxAge: TimeInterval = 300

    private let client: PublicAddressClient
    /// The network and time of the last answer.
    private var lookedUp: (network: String, date: Date)?
    private var isLookingUp = false

    public init(client: PublicAddressClient = .live) {
        self.client = client
    }

    public func refreshIfStale(path: NetworkPath?) async {
        guard isEnabled, let path, path.isSatisfied, !isLookingUp else { return }
        let network = "\(path.interface)|\(path.interfaceName ?? "")|\(path.isVPN)"
        if let lookedUp, lookedUp.network == network, client.now().timeIntervalSince(lookedUp.date) < Self.maxAge {
            return
        }
        if lookedUp?.network != network { address = nil }
        isLookingUp = true
        defer { isLookingUp = false }
        let answer = await client.fetch()
        guard isEnabled else { return }
        address = answer
        lookedUp = answer.map { _ in (network, client.now()) }
    }

    /// The `ip=` line of a Cloudflare trace, if it holds a real address.
    nonisolated static func ip(fromTrace data: Data) -> String? {
        let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first { $0.hasPrefix("ip=") }
        guard let candidate = line.map({ String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) }),
              isAddress(candidate) else { return nil }
        return candidate
    }

    private nonisolated static func isAddress(_ text: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return inet_pton(AF_INET, text, &ipv4) == 1 || inet_pton(AF_INET6, text, &ipv6) == 1
    }
}
