import Foundation

/// Checks for real internet access: a captive portal or Wi-Fi without internet fails.
nonisolated enum ReachabilityProbe {
    /// Apple's captive portal check: answers exactly "Success" when the internet is reachable.
    static let appleURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!
    /// Fallback when Apple's endpoint is down or blocked: answers 204 with no body.
    static let googleURL = URL(string: "https://www.google.com/generate_204")!
    /// Short enough that a dead connection shows quickly; both endpoints answer in well under it.
    static let timeout: TimeInterval = 3

    static func isAppleSuccess(statusCode: Int, body: Data) -> Bool {
        statusCode == 200 && String(decoding: body, as: UTF8.self).contains("<BODY>Success</BODY>")
    }

    /// Asks both at once: the first good answer wins, so a slow or blocked
    /// endpoint never adds its timeout to the other's.
    @concurrent
    static func check() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                guard let (body, status) = await fetch(appleURL) else { return false }
                return isAppleSuccess(statusCode: status, body: body)
            }
            group.addTask {
                await fetch(googleURL)?.1 == 204
            }
            for await isReachable in group where isReachable {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    @concurrent
    private static func fetch(_ url: URL) async -> (Data, Int)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        return (data, http.statusCode)
    }
}
