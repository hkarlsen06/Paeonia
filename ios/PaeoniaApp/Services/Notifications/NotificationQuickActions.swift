import Foundation
import UserNotifications

/// The buttons under a notification, set up in `PaeoniaNotificationCategory`.
nonisolated enum PaeoniaNotificationActionID {
    /// Type a reply to a chat message right from the notification.
    static let reply = "paeonia.reply"
    /// Send a heart to the message or drawing.
    static let heart = "paeonia.heart"

    static func isQuickAction(_ identifier: String) -> Bool {
        identifier == reply || identifier == heart
    }
}

/// What a quick action needs from the push. It is copied off `userInfo` because that is
/// not `Sendable`, and the action runs in a task. Every key is one the server puts in the
/// payload of the push (`handleThreadMessageCreated`, `enqueueWidgetUpdateAlert`), which the
/// notification service extension keeps when it rewrites an alert.
nonisolated struct NotificationQuickActionPush: Sendable, Equatable {
    let type: String?
    let coupleID: UUID?
    let threadID: UUID?
    let messageID: UUID?
    let questionID: UUID?
    let memoryID: UUID?
    let storyID: UUID?
    let revisionID: UUID?

    init(userInfo: [AnyHashable: Any]) {
        func uuid(_ key: String) -> UUID? {
            (userInfo[key] as? String).flatMap(UUID.init(uuidString:))
        }
        type = userInfo["type"] as? String
        coupleID = uuid("couple_id")
        threadID = uuid("thread_id")
        messageID = uuid("message_id")
        questionID = uuid("question_id")
        memoryID = uuid("memory_id")
        storyID = uuid("story_id")
        revisionID = uuid("revision_id")
    }

    /// What the chat of a message push is about: its question, memory or story.
    var chatSubject: ThreadChatSubject? {
        if let questionID { return .question(questionID) }
        if let memoryID { return .memory(memoryID) }
        if let storyID { return .story(storyID) }
        return nil
    }

    /// What the heart goes on: a chat message or the drawing's revision. Nil for a push that has
    /// nothing to react to.
    var reactionTarget: ReactionTarget? {
        switch type {
        case "thread_message_sent": messageID.map(ReactionTarget.threadMessage)
        case "widget_updated": revisionID.map(ReactionTarget.widgetDrawing)
        default: nil
        }
    }
}

/// Runs the buttons under a notification while the app may be closed. The delegate calls it
/// from `userNotificationCenter(_:didReceive:)`.
///
/// A reply goes into the same offline outbox as a message typed in the chat, then the outbox
/// sends once. If the phone is offline or iOS stops the app first, the reply stays in the
/// outbox and the app sends it the next time it opens. Both actions need an unlocked phone
/// (`authenticationRequired`) and the signed-in account the app already holds. A reply or a
/// heart that cannot even be saved or sent tells the person with a notification, so nothing
/// they wrote disappears without a word.
nonisolated enum NotificationQuickActionHandler {
    static let heart = "\u{2764}\u{FE0F}"
    /// iOS lets a background launch run about 30 seconds. This leaves room to report a failure.
    private static let sendTimeout: Duration = .seconds(15)

    static func handle(actionID: String, replyText: String?, push: NotificationQuickActionPush) async {
        switch actionID {
        case PaeoniaNotificationActionID.reply:
            await reply(replyText, to: push)
        case PaeoniaNotificationActionID.heart:
            await sendHeart(to: push)
        default:
            break
        }
    }

    // MARK: - Reply

    private static func reply(_ text: String?, to push: NotificationQuickActionPush) async {
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else { return }
        guard push.type == "thread_message_sent",
              let coupleID = push.coupleID,
              push.threadID != nil,
              let ownerUserID = await signedInUserID()
        else {
            await FailureNotice.post(.replyNotSent, replyText: body)
            return
        }

        do {
            guard let subject = push.chatSubject else {
                await FailureNotice.post(.replyNotSent, replyText: body)
                return
            }
            try await replyInChat(body, to: push, subject: subject, ownerUserID: ownerUserID)
        } catch {
            await FailureNotice.post(.replyNotSent, replyText: body)
            return
        }
        await flushOutbox(ownerUserID: ownerUserID, coupleID: coupleID)
    }

    /// Queues the reply like a message typed in the chat. `push` has the couple and the thread.
    /// The chat can be a question's, a memory's comments or a story's replies.
    private static func replyInChat(
        _ body: String,
        to push: NotificationQuickActionPush,
        subject: ThreadChatSubject,
        ownerUserID: UUID
    ) async throws {
        guard let coupleID = push.coupleID, let threadID = push.threadID else {
            throw ThreadChatServiceError.unavailable
        }
        let service = ThreadChatServiceFactory.makeDefault()
        let operation = await SyncClientOperationFactory.shared.makeOperation()
        _ = try await service.queueMessage(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            subject: subject,
            threadID: threadID,
            body: body,
            photos: nil,
            createThread: false,
            replyTo: nil,
            operation: operation
        )
        // Answering a message means reading it, so the partner sees it as read.
        await service.markThreadRead(ownerUserID: ownerUserID, threadID: threadID, through: Date())
        if let messageID = push.messageID {
            await service.markThreadReadOnServer(threadID: threadID, messageID: messageID)
        }
    }

    /// Sends the outbox once, with a service of its own, because a launch in the background
    /// has no signed-in screen to do it. Sending the same operation twice is safe, since the
    /// server runs each client operation once.
    private static func flushOutbox(ownerUserID: UUID, coupleID: UUID) async {
        let sync = PaeoniaSyncService(liveSync: nil)
        await sync.configure(session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID))
        await sync.flushPendingWrites(timeout: sendTimeout)
    }

    // MARK: - Heart

    private static func sendHeart(to push: NotificationQuickActionPush) async {
        guard let target = push.reactionTarget, await signedInUserID() != nil else {
            await FailureNotice.post(.heartNotSent, replyText: nil)
            return
        }
        do {
            try await LiveReactionGateway().setReaction(heart, on: target)
        } catch {
            await FailureNotice.post(.heartNotSent, replyText: nil)
        }
    }

    // MARK: - Account

    /// The user the app is signed in as, once Clerk has read its saved session. Nil when
    /// nobody is signed in or the phone is not paired, so an action never runs as someone else.
    private static func signedInUserID() async -> UUID? {
        guard await PaeoniaClerk.loadedAccountID(timeout: .seconds(8)) != nil else { return nil }
        return WidgetSyncIdentityStore.shared.load().currentUserID
    }
}

/// The notification that says a button did not work. A reply that could not be saved comes
/// back as the notification's text, so the person can copy it.
private nonisolated enum FailureNotice {
    enum Kind {
        case replyNotSent
        case heartNotSent
    }

    static func post(_ kind: Kind, replyText: String?) async {
        let content = UNMutableNotificationContent()
        switch kind {
        case .replyNotSent:
            content.title = String(localized: .notificationsQuickActionReplyFailedTitle)
            content.body = [String(localized: .notificationsQuickActionReplyFailedMessage), replyText]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .heartNotSent:
            content.title = String(localized: .notificationsQuickActionHeartFailedTitle)
            content.body = String(localized: .notificationsQuickActionHeartFailedMessage)
        }
        content.threadIdentifier = "quick-action-failed"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
