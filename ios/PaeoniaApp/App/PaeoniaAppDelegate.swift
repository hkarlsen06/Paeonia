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
        // A pause on location sharing just ended. Send where the phone is now.
        if (userInfo["type"] as? String) == "location_pause_ended" {
            await LocationUpdateController.shared.shareAfterPauseEnded()
            return .newData
        }
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
        if (userInfo["type"] as? String) == "badge_update" {
            await DeliveredNotifications.reconcile()
            return .newData
        }
        // The canvas service reloads the widget when it writes new files. An
        // extra reload here would spend the widget's daily budget on every push.
        await widgetSync.sync(identity: identityStore.load())
        await DeliveredNotifications.reconcile()
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

    /// Foreground pushes never show a system banner, play a push sound or enter
    /// Notification Center. Live activity uses its existing screen cues. Other
    /// notices use the app banner and keep their notification destination.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let userInfo = content.userInfo
        // Communication notifications can lose custom fields when rewritten.
        // Their thread identifier survives, so it also identifies drawings and chat.
        let isWidgetUpdate = (userInfo["type"] as? String) == "widget_updated"
            || (userInfo["route"] as? String) == "widget"
            || content.threadIdentifier == "widget"
        let type = (userInfo["type"] as? String)
            ?? (content.threadIdentifier.hasPrefix("chat:") ? "thread_message_sent" : "")
        let isGameActivity = type.hasPrefix("game_")
            || (type == "reaction_added" && userInfo["game_kind"] is String)

        // Keep this independent of notification type, including future types.
        // Badge-only pushes still update the icon without interrupting the person.
        defer { completionHandler(type == "badge_update" ? [.badge] : []) }

        #if DEBUG
        let detail = "widget=\(isWidgetUpdate) thread=\(content.threadIdentifier) type=\(type)"
        logger.debug("willPresent \(detail, privacy: .public)")
        #endif

        if isGameActivity {
            Task { @MainActor in
                LiveFeedDemand.shared.touch([.gameTurns])
            }
        }
        guard type != "badge_update", !isGameActivity, !Self.typesShownLiveInApp.contains(type) else {
            return
        }
        let title = content.title
        let body = content.body
        guard !title.isEmpty || !body.isEmpty else { return }
        let deepLink = isWidgetUpdate ? .widgetDrawing : PaeoniaDeepLink(notificationUserInfo: userInfo)
        let showsPartnerAvatar = isWidgetUpdate || userInfo["actor_user_id"] is String
        Task { @MainActor in
            PaeoniaNotificationRouter.shared.presentForegroundNotice(
                title: title.isEmpty ? nil : title,
                message: body, deepLink: deepLink, showsPartnerAvatar: showsPartnerAvatar
            )
        }
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
