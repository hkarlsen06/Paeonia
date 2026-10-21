import Foundation
#if DEBUG
import OSLog
#endif

/// The opt-in "question time" reminder: a time of day when Paeonia nudges you if you
/// have not started today's questions. It is off until the user turns it on.
nonisolated struct QuestionTimeReminder: Equatable, Sendable {
    static let defaultMinutes = 20 * 60

    var isEnabled = false
    /// Minutes after local midnight, 0 to 1439. The server turns it into a moment in the
    /// time zone of the phone the user used last.
    var minutes = QuestionTimeReminder.defaultMinutes

    /// The reminder time on `day`, for a time picker.
    func time(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: day
        ) ?? day
    }

    /// The minutes after midnight that a time picker's date shows.
    static func minutes(of time: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

nonisolated struct NotificationPreferences: Equatable, Sendable {
    var streakRemindersEnabled = true
    var dailyChallengeEnabled = true
    var partnerAnsweredEnabled = true
    var messagesEnabled = true
    var widgetUpdatesEnabled = true
    var memoriesEnabled = true
    var gamesEnabled = true
    var dateRemindersEnabled = true
    /// Off by default. On, the lock screen keeps who a notification is from and what it is
    /// while iOS hides previews (`PaeoniaNotificationCategory`). The server stores it as
    /// `lock_screen_detail_level`: "descriptive" when on, "private" when off.
    var lockScreenDetailsEnabled = false
    var questionTime = QuestionTimeReminder()
}

nonisolated extension NotificationPreferences {
    subscript(kind: NotificationPreferenceKind) -> Bool {
        get {
            switch kind {
            case .streakReminders: streakRemindersEnabled
            case .dailyChallenge: dailyChallengeEnabled
            case .partnerAnswered: partnerAnsweredEnabled
            case .messages: messagesEnabled
            case .widgetUpdates: widgetUpdatesEnabled
            case .memories: memoriesEnabled
            case .games: gamesEnabled
            case .dateReminders: dateRemindersEnabled
            case .lockScreenDetails: lockScreenDetailsEnabled
            }
        }
        set {
            switch kind {
            case .streakReminders: streakRemindersEnabled = newValue
            case .dailyChallenge: dailyChallengeEnabled = newValue
            case .partnerAnswered: partnerAnsweredEnabled = newValue
            case .messages: messagesEnabled = newValue
            case .widgetUpdates: widgetUpdatesEnabled = newValue
            case .memories: memoriesEnabled = newValue
            case .games: gamesEnabled = newValue
            case .dateReminders: dateRemindersEnabled = newValue
            case .lockScreenDetails: lockScreenDetailsEnabled = newValue
            }
        }
    }
}

nonisolated enum NotificationPreferenceKind: CaseIterable, Hashable, Sendable {
    case streakReminders
    case dailyChallenge
    case partnerAnswered
    case messages
    case widgetUpdates
    case memories
    case games
    /// Birthdays, the anniversary, milestones and countdowns.
    case dateReminders
    /// Not a column: the server keeps it as `lock_screen_detail_level` and sets it with its own call.
    case lockScreenDetails

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
        case .games:
            "games_enabled"
        case .dateReminders:
            "date_reminders_enabled"
        case .lockScreenDetails:
            "lock_screen_detail_level"
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

    /// Persists the question time reminder: the switch and its time in one request.
    func setQuestionTimeReminder(_ reminder: QuestionTimeReminder) async throws

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
        if kind == .lockScreenDetails {
            try await client.mutation(
                "identity:set_lock_screen_detail_level",
                args: SetLockScreenDetailLevelRequest(level: enabled ? "descriptive" : "private")
            )
            return
        }
        try await client.mutation(
            "identity:set_notification_preference",
            args: SetNotificationPreferenceRequest(column: kind.columnName, enabled: enabled)
        )
    }

    func setQuestionTimeReminder(_ reminder: QuestionTimeReminder) async throws {
        try await client.mutation(
            "identity:set_question_time_reminder",
            args: SetQuestionTimeReminderRequest(reminder: reminder)
        )
    }
}

nonisolated private struct SetLockScreenDetailLevelRequest: Encodable {
    let level: String

    enum CodingKeys: String, CodingKey {
        case level = "p_level"
    }
}

nonisolated struct SetQuestionTimeReminderRequest: Encodable {
    let reminder: QuestionTimeReminder

    enum CodingKeys: String, CodingKey {
        case enabled = "p_enabled"
        case minutes = "p_minutes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reminder.isEnabled, forKey: .enabled)
        // `v.number()` in the backend, so a Double.
        try container.encode(Double(reminder.minutes), forKey: .minutes)
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
    let gamesEnabled: Bool
    let dateRemindersEnabled: Bool
    let lockScreenDetailLevel: String
    let questionTimeEnabled: Bool
    let questionTimeMinutes: Int

    var preferences: NotificationPreferences {
        NotificationPreferences(
            streakRemindersEnabled: streakRemindersEnabled,
            dailyChallengeEnabled: dailyChallengeEnabled,
            partnerAnsweredEnabled: partnerAnsweredEnabled,
            messagesEnabled: messagesEnabled,
            widgetUpdatesEnabled: widgetUpdatesEnabled,
            memoriesEnabled: memoriesEnabled,
            gamesEnabled: gamesEnabled,
            dateRemindersEnabled: dateRemindersEnabled,
            lockScreenDetailsEnabled: lockScreenDetailLevel == "descriptive",
            questionTime: QuestionTimeReminder(isEnabled: questionTimeEnabled, minutes: questionTimeMinutes)
        )
    }

    enum CodingKeys: String, CodingKey {
        case streakRemindersEnabled = "streak_reminders_enabled"
        case dailyChallengeEnabled = "daily_challenge_enabled"
        case partnerAnsweredEnabled = "partner_answered_enabled"
        case messagesEnabled = "messages_enabled"
        case widgetUpdatesEnabled = "widget_updates_enabled"
        case memoriesEnabled = "memories_enabled"
        case gamesEnabled = "games_enabled"
        case dateRemindersEnabled = "date_reminders_enabled"
        case lockScreenDetailLevel = "lock_screen_detail_level"
        case questionTimeEnabled = "question_time_enabled"
        case questionTimeMinutes = "question_time_minutes"
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
