import Foundation

/// The couple's shared connection streak, as stored on the server.
///
/// The backend owns this value: meaningful activity such as completing the daily
/// challenge, sharing a drawing, adding a memory, or sending a message updates
/// `streak_states` (consecutive-day counting, per-couple timezone day boundaries,
/// shared between partners). The app only reads it.
nonisolated struct CoupleStreak: Equatable, Sendable {
    var currentCount: Int
    var longestCount: Int
    /// The couple's local date (`yyyy-MM-dd`) the streak last counted, or `nil`
    /// if it has never counted. Used to predict today's increment before the
    /// just-sent answer has synced.
    var lastQualifiedDate: String?
    var restoreAvailable: Bool
    /// The streak length a paid restore would bring back, or `0` when there is
    /// nothing to restore. Shown to the user as "get your N-day streak back".
    var restorableCount: Int
    /// When the restore offer closes, or `nil` when nothing is restorable.
    var restoreDeadline: Date?

    /// True while a broken streak can still be bought back. Recomputed from the
    /// deadline (not just the server flag) so the offer disappears the moment it
    /// lapses, even while the app stays open.
    var isRestorable: Bool {
        restorableCount > 0 && (restoreDeadline.map { $0 > .now } ?? false)
    }

    static let none = CoupleStreak(
        currentCount: 0,
        longestCount: 0,
        lastQualifiedDate: nil,
        restoreAvailable: false,
        restorableCount: 0,
        restoreDeadline: nil
    )
}

/// Pure logic for the number shown on the completion celebration.
///
/// Answers are sent local-first, so when the celebration appears the server
/// streak may not yet reflect today's completion. Rather than wait on the
/// network (which would stall the moment, and never resolve offline), we predict
/// the post-completion count from the stored streak and the couple day identity.
/// The server read model has already reduced an expired streak to zero; date-gap
/// math must not reset a still-live streak because travel can skip a date.
enum StreakCelebration {
    /// The streak to show now that the user has finished today's challenge.
    ///
    /// - `serverCurrentCount`: the stored `current_count` (through `lastQualifiedDate`).
    /// - `lastQualifiedDate` / `todayLocalDate`: couple-local dates as `yyyy-MM-dd`.
    static func celebratedCount(
        serverCurrentCount: Int,
        lastQualifiedDate: String?,
        todayLocalDate: String?
    ) -> Int {
        guard let todayLocalDate else {
            // No local date to reason about — show the stored count, but never 0
            // on a screen the user only reaches by completing today.
            return max(serverCurrentCount, 1)
        }

        guard let lastQualifiedDate else {
            // Never counted before: today is day one.
            return 1
        }

        if lastQualifiedDate == todayLocalDate {
            // Already counted today (the user earlier, or their partner).
            return max(serverCurrentCount, 1)
        }

        // A different couple day extends a live count. Date adjacency is not a
        // reliable signal once a partner crosses time zones or the date line.
        return max(serverCurrentCount + 1, 1)
    }
}
