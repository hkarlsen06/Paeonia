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
        PaeoniaNotificationCategory.registerAll()
        // iOS relaunches a closed app in the background after a significant
        // move. The location manager must be ready before this returns so the
        // position reaches it.
        LocationUpdateController.shared.resumeAfterLaunch()
        // Off the main thread, because setting the category can block for a moment.
        Task.detached(priority: .utility) { PaeoniaAudioSession.useAmbient() }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.paeoniaHexString
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
    /// `userInfo` is not `Sendable`. Only the id of a taken-back message is read from it.
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        // The sender took a message back. Its alert goes, and so do its text and files in the
        // chat history on this phone, which would otherwise show it until the chat is opened.
        if let deletedMessageID = DeliveredNotifications.deletedMessageID(in: userInfo) {
            await DeliveredNotifications.clearMessage(deletedMessageID)
            if let ownerUserID = identityStore.load().currentUserID {
                await ThreadChatServiceFactory.makeDefault()
                    .applyRemoteDeletion(ownerUserID: ownerUserID, messageID: deletedMessageID)
            }
            return .newData
        }
        // The canvas service reloads the widget when it writes new files. An
        // extra reload here would spend the widget's daily budget on every push.
        await widgetSync.sync(identity: identityStore.load())
        return .newData
    }

    nonisolated private static let typesShownLiveInApp: Set<String> = [
        "thread_message_sent",
        "partner_answered",
        // The Topics card on the Questions tab shows what's waiting.
        "topics_waiting",
        "daily_challenge_completed",
        // The open app plays the pairing celebration the moment the partner joins.
        "partner_joined",
    ]

    /// While the app is open, suppress the system banner for a partner's widget
    /// update and surface it as an in-app top banner instead (like the rest of
    /// the app's notices). Question activity and a partner joining show no banner. Other
    /// notifications show a banner but stay out of Notification Center, since the
    /// person already saw it in the app. The sender name
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
        // thread identifier ("widget", or "chat:<thread>" for a message) survives
        // that rewrite.
        let userInfo = content.userInfo
        let isWidgetUpdate = (userInfo["type"] as? String) == "widget_updated"
            || (userInfo["route"] as? String) == "widget"
            || content.threadIdentifier == "widget"

        let type = (userInfo["type"] as? String)
            ?? (content.threadIdentifier.hasPrefix("chat:") ? "thread_message_sent" : "")

        #if DEBUG
        let detail = "widget=\(isWidgetUpdate) thread=\(content.threadIdentifier) type=\(type)"
        logger.debug("willPresent \(detail, privacy: .public)")
        #endif

        // A game push means the Games tab badge and the Home game card are out of
        // date. The game feeds run for a short while and bring in the new turn.
        if type.hasPrefix("game_") {
            Task { @MainActor in
                LiveFeedDemand.shared.touch([.gameTurns])
            }
        }

        // A badge-only push shows nothing. Its number goes on the icon.
        if type == "badge_update" {
            completionHandler([.badge])
            return
        }

        // Question activity and a partner joining already show live in the
        // app, so drop the system banner while the app is open.
        if Self.typesShownLiveInApp.contains(type) {
            completionHandler([])
            return
        }

        guard isWidgetUpdate else {
            completionHandler([.banner, .sound])
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

    /// Tapping a notification routes through the typed SwiftUI deep-link relay.
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
        let content = response.notification.request.content
        let userInfo = content.userInfo

        // A button under the notification (reply, heart) runs without opening the app. iOS keeps
        // the app awake until the completion handler runs, and that call must stay on the main thread.
        if PaeoniaNotificationActionID.isQuickAction(response.actionIdentifier) {
            let actionID = response.actionIdentifier
            let replyText = (response as? UNTextInputNotificationResponse)?.userText
            let push = NotificationQuickActionPush(userInfo: userInfo)
            nonisolated(unsafe) let finish = completionHandler
            Task { @MainActor in
                await NotificationQuickActionHandler.handle(actionID: actionID, replyText: replyText, push: push)
                finish()
            }
            return
        }

        if let deepLink = PaeoniaDeepLink(notificationUserInfo: userInfo) {
            Task { @MainActor in
                PaeoniaNotificationRouter.shared.route(deepLink)
            }
        }
        completionHandler()
    }
}
