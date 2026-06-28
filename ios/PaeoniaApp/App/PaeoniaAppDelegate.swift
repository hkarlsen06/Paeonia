import UIKit
import UserNotifications
#if DEBUG
import OSLog
#endif

/// SwiftUI's `App` lifecycle does not surface APNs device-token or silent-push
/// callbacks, so these go through a `UIApplicationDelegate` bridged via
/// `@UIApplicationDelegateAdaptor`.
final class PaeoniaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let pushRegistration: any PushRegistering = PushRegistrationServiceFactory.makeDefault()
    private let widgetSync: any WidgetCanvasSyncing = WidgetCanvasSyncServiceFactory.makeDefault()
    private let identityStore = WidgetSyncIdentityStore.shared

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Push"
    )
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Required so a tapped widget alert (and foreground presentation) reaches
        // the delegate methods below.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await pushRegistration.registerDevice(pushToken: token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        #if DEBUG
        logger.error("Remote notification registration failed: \(String(describing: error))")
        #endif
    }

    /// Silent (content-available) push: wake, pull the partner's latest drawing
    /// into the widget, and report whether new data arrived.
    ///
    /// `nonisolated` because the protocol requirement is nonisolated and
    /// `userInfo` is not `Sendable`; we never read it, only kick off the sync.
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await widgetSync.sync(identity: identityStore.load())
        await WidgetCenterReloader().reloadWidget()
        return .newData
    }

    /// While the app is open, suppress the system banner for a partner's widget
    /// update and surface it as an in-app top banner instead (like the rest of
    /// the app's notices). Other notifications present normally. The sender name
    /// and localized body are read off the content before crossing to the main
    /// actor, since `userInfo` is not `Sendable`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        // Detect a widget update from several signals: the notification service
        // extension rewrites the alert into a communication notification before
        // this runs, and `updating(from:)` can drop custom `userInfo`. The
        // thread identifier it sets ("widget:<sender>") survives that rewrite.
        let userInfo = content.userInfo
        let isWidgetUpdate = (userInfo["type"] as? String) == "widget_updated"
            || (userInfo["route"] as? String) == "widget"
            || content.threadIdentifier.hasPrefix("widget:")

        #if DEBUG
        let type = (userInfo["type"] as? String) ?? "nil"
        let detail = "widget=\(isWidgetUpdate) thread=\(content.threadIdentifier) type=\(type)"
        logger.debug("willPresent \(detail, privacy: .public)")
        #endif

        guard isWidgetUpdate else {
            completionHandler([.banner, .sound, .list])
            return
        }

        let title = content.title
        let body = content.body
        Task { @MainActor in
            PaeoniaNotificationRouter.shared.presentForegroundNotice(
                title: title.isEmpty ? nil : title,
                message: body
            )
        }
        // Suppress the system presentation entirely so nothing piles up in
        // Notification Center while the user is already in the app.
        completionHandler([])
    }

    /// Tapping a widget alert opens the drawing screen.
    ///
    /// Uses the completion-handler form (not the `async` variant): UIKit calls it
    /// on the main thread and performs snapshot/state-restoration work right after
    /// it returns, and that work asserts it is on the main thread. The `async`
    /// variant runs on a background cooperative thread and crashes UIApplication
    /// when that post-completion work fires off-main.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let isWidgetUpdate = (userInfo["type"] as? String) == "widget_updated"
            || (userInfo["route"] as? String) == "widget"
        if isWidgetUpdate {
            Task { @MainActor in
                PaeoniaNotificationRouter.shared.route(.drawing)
            }
        }
        completionHandler()
    }
}
