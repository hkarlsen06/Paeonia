import Foundation
#if DEBUG
import OSLog
#endif

nonisolated struct NotificationPreferences: Equatable, Sendable {
    var streakRemindersEnabled = true
    var dailyChallengeEnabled = true
    var partnerAnsweredEnabled = true
    var messagesEnabled = true
    var widgetUpdatesEnabled = true
    var memoriesEnabled = true
}

nonisolated enum NotificationPreferenceKind: Hashable, Sendable {
    case streakReminders
    case dailyChallenge
    case partnerAnswered
    case messages
    case widgetUpdates
    case memories

    var columnName: String {
        switch self {
        case .streakReminders:
            "streak_reminders_enabled"
        case .dailyChallenge:
            "daily_challenge_enabled"
        case .partnerAnswered:
            "partner_answered_enabled"
        case .messages:
            "messages_enabled"
        case .widgetUpdates:
            "widget_updates_enabled"
        case .memories:
            "memories_enabled"
        }
    }
}

/// Reads and writes the couple member's notification preferences. The visible
/// widget alert is user-toggleable; the separate silent widget refresh is not.
/// The backend returns and updates only the signed-in user's row.
nonisolated protocol NotificationPreferencesProviding: Sendable {
    /// Loads all user-facing MVP notification toggles.
    func loadNotificationPreferences() async throws -> NotificationPreferences

    /// Persists one user-facing notification toggle.
    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws

    /// Emits the preferences now and again whenever they change on the server.
    /// The stream ends when the consuming task is cancelled.
    func notificationPreferenceUpdates() -> AsyncStream<NotificationPreferences>
}

nonisolated extension NotificationPreferencesProviding {
    /// Providers without a live source emit nothing.
    func notificationPreferenceUpdates() -> AsyncStream<NotificationPreferences> {
        AsyncStream { $0.finish() }
    }
}

actor ConvexNotificationPreferencesService: NotificationPreferencesProviding {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func loadNotificationPreferences() async throws -> NotificationPreferences {
        let row: NotificationPreferencesRow = try await client.query(
            "identity:get_notification_preferences"
        )

        return row.preferences
    }

    nonisolated func notificationPreferenceUpdates() -> AsyncStream<NotificationPreferences> {
        ScreenLiveUpdates.values(
            "identity:get_notification_preferences",
            as: NotificationPreferencesRow.self,
            map: \.preferences
        )
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws {
        try await client.mutation(
            "identity:set_notification_preference",
            args: SetNotificationPreferenceRequest(column: kind.columnName, enabled: enabled)
        )
    }
}

nonisolated private struct SetNotificationPreferenceRequest: Encodable {
    let column: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case column = "p_column"
        case enabled = "p_enabled"
    }
}

// `nonisolated` so the Decodable conformance is usable from the actor's decode,
// not pinned to the main actor under default isolation.
nonisolated private struct NotificationPreferencesRow: Decodable {
    let streakRemindersEnabled: Bool
    let dailyChallengeEnabled: Bool
    let partnerAnsweredEnabled: Bool
    let messagesEnabled: Bool
    let widgetUpdatesEnabled: Bool
    let memoriesEnabled: Bool

    var preferences: NotificationPreferences {
        NotificationPreferences(
            streakRemindersEnabled: streakRemindersEnabled,
            dailyChallengeEnabled: dailyChallengeEnabled,
            partnerAnsweredEnabled: partnerAnsweredEnabled,
            messagesEnabled: messagesEnabled,
            widgetUpdatesEnabled: widgetUpdatesEnabled,
            memoriesEnabled: memoriesEnabled
        )
    }

    enum CodingKeys: String, CodingKey {
        case streakRemindersEnabled = "streak_reminders_enabled"
        case dailyChallengeEnabled = "daily_challenge_enabled"
        case partnerAnsweredEnabled = "partner_answered_enabled"
        case messagesEnabled = "messages_enabled"
        case widgetUpdatesEnabled = "widget_updates_enabled"
        case memoriesEnabled = "memories_enabled"
    }
}

nonisolated enum NotificationPreferencesServiceFactory {
    static func makeDefault() -> (any NotificationPreferencesProviding)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return nil
        }
        return ConvexNotificationPreferencesService(client: client)
    }
}
