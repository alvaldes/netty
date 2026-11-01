import AppKit
@preconcurrency import UserNotifications

/// One system notification.
nonisolated public struct StatusNotification: Sendable, Equatable {
    public var title: String
    public var body: String
    /// A later notification with the same identifier replaces this one.
    public var identifier: String
    /// Opened when the notification is clicked.
    public var url: URL?

    /// One identifier for every status notification, so "Back online" replaces "Connection lost".
    public init(title: String, body: String, identifier: String = "connection-status", url: URL? = nil) {
        self.title = title
        self.body = body
        self.identifier = identifier
        self.url = url
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
            if let url = notification.url { content.userInfo = ["url": url.absoluteString] }
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    )
}

/// Shows notifications while the popover is open too (macOS hides them for the
/// active app by default) and opens a notification's link when it is clicked.
nonisolated private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
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
