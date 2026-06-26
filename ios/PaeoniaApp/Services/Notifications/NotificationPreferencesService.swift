import Foundation
import Supabase
#if DEBUG
import OSLog
#endif

/// Reads and writes the couple member's notification preferences. For MVP the
/// only user-facing toggle is the widget drawing alert, backed by
/// `notification_preferences.widget_updates_enabled` (the silent refresh is not
/// user-controllable). Row access is scoped to the caller by RLS.
nonisolated protocol NotificationPreferencesProviding: Sendable {
    /// Whether the partner's drawing updates should show a notification banner.
    func loadWidgetAlertsEnabled() async throws -> Bool

    /// Persists the widget drawing alert toggle.
    func setWidgetAlertsEnabled(_ enabled: Bool) async throws
}

actor SupabaseNotificationPreferencesService: NotificationPreferencesProviding {
    private let client: SupabaseClient
    private static let table = "notification_preferences"
    private static let widgetAlertsColumn = "widget_updates_enabled"

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadWidgetAlertsEnabled() async throws -> Bool {
        let row: WidgetAlertPreferenceRow = try await client
            .from(Self.table)
            .select(Self.widgetAlertsColumn)
            .single()
            .execute()
            .value

        return row.widgetUpdatesEnabled
    }

    func setWidgetAlertsEnabled(_ enabled: Bool) async throws {
        // RLS limits the update to the caller's own row, matching the existing
        // table-access pattern elsewhere in the app.
        try await client
            .from(Self.table)
            .update([Self.widgetAlertsColumn: enabled])
            .execute()
    }
}

// `nonisolated` so the Decodable conformance is usable from the actor's decode,
// not pinned to the main actor under default isolation.
nonisolated private struct WidgetAlertPreferenceRow: Decodable {
    let widgetUpdatesEnabled: Bool

    enum CodingKeys: String, CodingKey {
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
