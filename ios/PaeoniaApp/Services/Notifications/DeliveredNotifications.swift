import SwiftUI
import UserNotifications

/// Removes alerts from Notification Center once the person has seen what they
/// point to in the app, so old alerts don't pile up. Alerts are matched on the
/// `type` and ids the server puts in every push, which the notification service
/// extension keeps when it rewrites a drawing or chat alert. Content alerts are
/// matched by id against what is on screen, so an alert for something that
/// hasn't reached this phone yet stays.
nonisolated enum DeliveredNotifications {
    /// The Questions tab is open, so the "question time" reminder has done its job.
    static func clearQuestionTimeReminders() async {
        await clear(types: ["question_time_reminder"])
    }

    /// Removes every delivered alert of these kinds, for example `widget_updated`.
    static func clear(types: Set<String>) async {
        await remove { userInfo in
            (userInfo["type"] as? String).map(types.contains) ?? false
        }
    }

    /// The person opened this question and saw the partner's answer: its reveal
    /// alert is read, and "answered today's question" has done its job. A question's
    /// page shows every day it came up, so it passes all their instance ids. One
    /// "answered too" alert can cover several questions, and opening any of them
    /// clears it. Chat alerts go only for the messages on screen.
    static func clearQuestion(instanceIDs: Set<UUID>, shownMessageIDs: Set<UUID> = []) async {
        await remove { userInfo in
            switch userInfo["type"] as? String {
            case "daily_challenge_completed":
                true
            case "partner_answered":
                ((userInfo["instance_ids"] as? [Any]) ?? []).contains { uuid($0).map(instanceIDs.contains) ?? false }
            case "thread_message_sent":
                uuid(userInfo["message_id"]).map(shownMessageIDs.contains) ?? false
            default:
                false
            }
        }
    }

    /// The person opened a memory's comments or a story's replies and saw these messages.
    static func clearMessages(_ messageIDs: Set<UUID>) async {
        guard !messageIDs.isEmpty else { return }
        await remove { userInfo in
            (userInfo["type"] as? String) == "thread_message_sent"
                && (uuid(userInfo["message_id"]).map(messageIDs.contains) ?? false)
        }
    }

    /// The id in the silent push that says a sender took a message back, nil for any other push.
    static func deletedMessageID(in userInfo: [AnyHashable: Any]) -> UUID? {
        guard (userInfo["type"] as? String) == "thread_message_deleted" else { return nil }
        return uuid(userInfo["message_id"])
    }

    /// The sender took this message back, so its alert must not stay on the lock screen.
    static func clearMessage(_ messageID: UUID) async {
        await remove { userInfo in
            (userInfo["type"] as? String) == "thread_message_sent"
                && (uuid(userInfo["message_id"]) == messageID)
        }
    }

    /// The Memories timeline shows these memories.
    static func clearMemories(shownMemoryIDs: Set<UUID>) async {
        guard !shownMemoryIDs.isEmpty else { return }
        await remove { userInfo in
            (userInfo["type"] as? String) == "memory_created"
                && (uuid(userInfo["memory_id"]).map(shownMemoryIDs.contains) ?? false)
        }
    }

    /// Signing out or losing access to the relationship leaves nothing behind
    /// that names the partner.
    static func clearAll() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        // Nothing waits any more, so the icon number goes too.
        Task { await AppBadgeLiveFeed.clear() }
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func remove(where matches: ([AnyHashable: Any]) -> Bool) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.deliveredNotifications()
            .filter { matches($0.request.content.userInfo) }
            .map(\.request.identifier)
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

extension View {
    /// Removes a delivered "question time" reminder while this screen is showing, and again
    /// each time the app comes back to the foreground with it still showing.
    func clearsDeliveredQuestionTimeReminders() -> some View {
        modifier(ClearQuestionTimeRemindersModifier())
    }
}

private struct ClearQuestionTimeRemindersModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                await DeliveredNotifications.clearQuestionTimeReminders()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await DeliveredNotifications.clearQuestionTimeReminders() }
            }
    }
}
