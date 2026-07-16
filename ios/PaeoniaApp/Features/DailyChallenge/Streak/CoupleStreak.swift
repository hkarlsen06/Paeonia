import Foundation

/// The couple's shared connection streak, as stored on the server.
///
/// The backend owns this value. Each partner must do at least one meaningful
/// activity during the couple day before it counts: completing the daily
/// challenge, sharing a drawing, adding a memory, or sending a message. The app
/// reads the shared count and each person's current-day participation state.
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
    /// Used by the local-first completion UI. The server event can trail the
    /// just-finished local answer, so this says whether the current user's action
    /// was already represented by the last snapshot.
    var currentUserContributedToday = false
    /// True when the other partner already has a qualifying event today. Only in
    /// that case may the app predict that the user's just-finished challenge will
    /// advance the shared streak before the server refresh lands.
    var partnerContributedToday = false

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
/// streak may not yet reflect today's completion. We can only predict an advance
/// when the snapshot already confirms the partner contributed today; otherwise
/// the stored count stays visible until both people have shown up.
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
        todayLocalDate: String?,
        partnerContributedToday: Bool
    ) -> Int {
        guard let todayLocalDate else {
            return max(serverCurrentCount, 0)
        }

        guard let lastQualifiedDate else {
            // The first day begins only when the partner has also contributed.
            return partnerContributedToday ? 1 : 0
        }

        if lastQualifiedDate == todayLocalDate {
            return max(serverCurrentCount, 0)
        }

        guard partnerContributedToday else {
            return max(serverCurrentCount, 0)
        }

        // A different couple day extends a live count once both people have
        // contributed. Date adjacency is not reliable across time-zone travel.
        return max(serverCurrentCount + 1, 1)
    }
}
