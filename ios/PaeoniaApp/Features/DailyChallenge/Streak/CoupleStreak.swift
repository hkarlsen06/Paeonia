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
    /// The length of a broken streak that can still come back, free on the save
    /// day and by purchase on the two days after it, or `0` when nothing can.
    var restorableCount: Int
    /// When the restore days end, or `nil` when nothing can come back.
    var restoreDeadline: Date?
    /// Used by the local-first completion UI. The server event can trail the
    /// just-finished local answer, so this says whether the current user's action
    /// was already represented by the last snapshot.
    var currentUserContributedToday = false
    /// True when the other partner already has a qualifying event today. Only in
    /// that case may the app predict that the user's just-finished challenge will
    /// advance the shared streak before the server refresh lands.
    var partnerContributedToday = false
    /// True when a free freeze would cover a missed day of this streak. The server
    /// gives each couple one every 30 days, for streaks of three days or more.
    var freezeAvailable = false
    /// When the next free freeze is ready, or `nil` when one is ready now.
    var freezeReadyAt: Date?
    /// True when the couple missed a day and a freeze is keeping the streak alive.
    var freezeSavedStreak = false
    /// When a live streak ends unless both partners show up first, or `nil` when
    /// there is no live streak.
    var endsAt: Date?
    /// When the free save day of a broken streak ends, or `nil` when nothing can
    /// come back. If both partners do one small thing before then, the server
    /// brings the streak back on its own.
    var saveDeadline: Date?
    /// The couple's local date (`yyyy-MM-dd`) on which both partners last brought
    /// a broken streak back for free, or `nil` if they never have.
    var savedOn: String?

    /// True while both partners can still bring a broken streak back for free by
    /// doing one small thing today. Recomputed from the deadline, so it ends the
    /// moment the save day does, even while the app stays open.
    var isSavable: Bool {
        restorableCount > 0 && (saveDeadline.map { $0 > .now } ?? false)
    }

    /// True while a broken streak can be bought back: after its free save day and
    /// before the restore days end. Recomputed from the deadlines (not just the
    /// server flag) so the offer opens and closes on time while the app stays open.
    var isRestorable: Bool {
        restorableCount > 0 && !isSavable && (restoreDeadline.map { $0 > .now } ?? false)
    }

    /// The save day to celebrate: the day both partners brought the streak back
    /// for free, while it is still the streak's newest day.
    var freshSaveDay: String? {
        guard currentCount > 0, let savedOn, savedOn == lastQualifiedDate else { return nil }
        return savedOn
    }

    /// The single surface a streak entry point should open. A broken streak that
    /// can be bought back goes straight to the purchase offer, a streak sitting on
    /// a milestone replays its celebration, and other streaks, one waiting on its
    /// free save day included, open the informative sheet. Keeping this decision
    /// shared prevents a notification or toolbar entry from inserting a duplicate
    /// detail screen before purchase.
    var entryDestination: StreakEntryDestination {
        if isRestorable { return .restore }
        if StreakMilestones.isMilestone(currentCount) { return .milestone(currentCount) }
        return .detail
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

/// The freeze line on the streak sheet.
nonisolated enum StreakFreezeNote: Equatable, Sendable {
    /// A freeze kept the streak alive after a missed day.
    case savedStreak
    /// A freeze is ready to cover the next missed day.
    case ready
    /// The last freeze was used. The next one is ready on this date.
    case readyOn(Date)
}

extension CoupleStreak {
    /// What the streak sheet says about the free freeze, or `nil` when there is
    /// no live streak or no freeze to mention.
    func freezeNote(now: Date = .now) -> StreakFreezeNote? {
        guard currentCount > 0 else { return nil }
        if freezeSavedStreak { return .savedStreak }
        if let freezeReadyAt, freezeReadyAt > now { return .readyOn(freezeReadyAt) }
        return freezeAvailable ? .ready : nil
    }
}

nonisolated enum StreakEntryDestination: Equatable, Sendable {
    case detail
    case restore
    case milestone(Int)
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
    /// - `savableCount`: the broken streak's length while today is its free save day, otherwise `0`.
    static func celebratedCount(
        serverCurrentCount: Int,
        lastQualifiedDate: String?,
        todayLocalDate: String?,
        partnerContributedToday: Bool,
        savableCount: Int = 0
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

        // Both showing up on the save day brings the broken streak back, and today
        // counts on top of it. The missed day does not count.
        if savableCount > 0 {
            return savableCount + 1
        }

        // A different couple day extends a live count once both people have
        // contributed. Date adjacency is not reliable across time-zone travel.
        return max(serverCurrentCount + 1, 1)
    }
}
