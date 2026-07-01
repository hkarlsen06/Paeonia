import Foundation
import Supabase
#if DEBUG
import OSLog
#endif

nonisolated struct NotificationPreferences: Equatable, Sendable {
    var streakRemindersEnabled = true
    var dailyChallengeEnabled = true
    var partnerAnsweredEnabled = true
    var widgetUpdatesEnabled = true
}

nonisolated enum NotificationPreferenceKind: Equatable, Sendable {
    case streakReminders
    case dailyChallenge
    case partnerAnswered
    case widgetUpdates

    var columnName: String {
        switch self {
        case .streakReminders:
            "streak_reminders_enabled"
        case .dailyChallenge:
            "daily_challenge_enabled"
        case .partnerAnswered:
            "partner_answered_enabled"
        case .widgetUpdates:
            "widget_updates_enabled"
        }
    }
}

/// Reads and writes the couple member's notification preferences. The visible
/// widget alert is user-toggleable; the separate silent widget refresh is not.
/// Row access is scoped to the caller by RLS.
nonisolated protocol NotificationPreferencesProviding: Sendable {
    /// Loads all user-facing MVP notification toggles.
    func loadNotificationPreferences() async throws -> NotificationPreferences

    /// Persists one user-facing notification toggle.
    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws
}

actor SupabaseNotificationPreferencesService: NotificationPreferencesProviding {
    private let client: SupabaseClient
    private static let table = "notification_preferences"
    private static let columns = "streak_reminders_enabled,daily_challenge_enabled,partner_answered_enabled,widget_updates_enabled"

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadNotificationPreferences() async throws -> NotificationPreferences {
        let row: NotificationPreferencesRow = try await client
            .from(Self.table)
            .select(Self.columns)
            .single()
            .execute()
            .value

        return row.preferences
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws {
        let session = try await client.auth.session

        try await client
            .from(Self.table)
            .update([kind.columnName: enabled])
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
    }
}

// `nonisolated` so the Decodable conformance is usable from the actor's decode,
// not pinned to the main actor under default isolation.
nonisolated private struct NotificationPreferencesRow: Decodable {
    let streakRemindersEnabled: Bool
    let dailyChallengeEnabled: Bool
    let partnerAnsweredEnabled: Bool
    let widgetUpdatesEnabled: Bool

    var preferences: NotificationPreferences {
        NotificationPreferences(
            streakRemindersEnabled: streakRemindersEnabled,
            dailyChallengeEnabled: dailyChallengeEnabled,
            partnerAnsweredEnabled: partnerAnsweredEnabled,
            widgetUpdatesEnabled: widgetUpdatesEnabled
        )
    }

    enum CodingKeys: String, CodingKey {
        case streakRemindersEnabled = "streak_reminders_enabled"
        case dailyChallengeEnabled = "daily_challenge_enabled"
        case partnerAnsweredEnabled = "partner_answered_enabled"
        case widgetUpdatesEnabled = "widget_updates_enabled"
    }
}

nonisolated enum NotificationPreferencesServiceFactory {
    static func makeDefault() -> (any NotificationPreferencesProviding)? {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return nil
        }
        return SupabaseNotificationPreferencesService(client: client)
    }
}
