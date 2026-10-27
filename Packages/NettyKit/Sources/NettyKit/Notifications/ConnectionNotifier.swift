import Foundation
@preconcurrency import UserNotifications

/// One system notification.
nonisolated public struct StatusNotification: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// The system services the notifier depends on, replaceable in tests.
nonisolated public struct NotificationClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Void
    public var post: @Sendable (StatusNotification) -> Void

    public init(requestAuthorization: @escaping @Sendable () async -> Void,
                post: @escaping @Sendable (StatusNotification) -> Void) {
        self.requestAuthorization = requestAuthorization
        self.post = post
    }

    /// One identifier for every status notification, so "Back online" replaces "Connection lost".
    private static let identifier = "connection-status"

    public static let live = NotificationClient(
        requestAuthorization: {
            UNUserNotificationCenter.current().delegate = ForegroundPresenter.shared
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        },
        post: { notification in
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    )
}

/// Shows notifications while the popover is open too: macOS hides them for the active app by default.
nonisolated private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Notifies when the connection goes offline and when it comes back. Quality
/// changes (online ⇄ degraded) never notify.
@Observable
public final class ConnectionNotifier {
    public var notifiesWhenOffline = true
    public var notifiesWhenBackOnline = true

    private let client: NotificationClient
    private let locale: Locale
    private var offlineSince: Date?

    public init(client: NotificationClient = .live, locale: Locale = .current) {
        self.client = client
        self.locale = locale
    }

    public func requestAuthorization() async {
        await client.requestAuthorization()
    }

    public func statusChanged(from old: ConnectionStatus?, to new: ConnectionStatus?, at date: Date) {
        if new == .offline {
            offlineSince = date
            // At launch nobody saw the connection drop, so there is nothing to tell.
            guard old != nil, notifiesWhenOffline else { return }
            client.post(StatusNotification(title: "Connection lost", body: "Netty can't reach the internet."))
        } else if old == .offline, new != nil {
            let downtime = offlineSince.map { date.timeIntervalSince($0) }
            offlineSince = nil
            guard notifiesWhenBackOnline else { return }
            let body = downtime.map { "You were offline for \(StatusDuration.text(seconds: $0, locale: locale))." }
                ?? "Your internet connection is back."
            client.post(StatusNotification(title: "Back online", body: body))
        }
    }
}
