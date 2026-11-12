import Foundation

/// The couple's shared connection streak, as stored on the server.
///
/// The backend owns this value and every rule behind it (`backend/convex/lib/streaks.ts`).
/// Each partner must do at least one meaningful activity during the couple day
/// before it counts: completing the daily challenge, sharing a drawing, adding a
/// memory, or sending a message. Up to 14 days in a row the partners spend together
/// need nothing. The app reads the shared count and each person's current-day
/// participation state.
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
    /// When the streak rests because the partners are together, from the server: the
    /// resting days that hold now, or else the next ones. The phone compares the time with
    /// it, so a cached streak still tells a resting day from the first day apart.
    var rest: Range<Date>?

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

    /// True when a live streak needs nothing at `now` because the partners are together.
    /// A broken streak never rests.
    func restsWhileTogether(at now: Date) -> Bool {
        currentCount > 0 && rest?.contains(now) == true
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
        if freezeSavedStreak && currentCount > 0 { return .detail }
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

/// Who has done something for the streak today, and how long the day still runs.
nonisolated struct StreakToday: Equatable, Sendable {
    var ownDone: Bool
    var partnerDone: Bool
    /// When today's chance ends, or nil when nothing is at stake (both done, resting, no live streak and no save day).
    var deadline: Date?
    var isResting: Bool
}

extension CoupleStreak {
    /// Today on the streak sheet. A save day counts down to its own end. While the
    /// partners are together the streak needs nothing, so both count as done.
    func today(at now: Date) -> StreakToday {
        if restsWhileTogether(at: now) {
            return StreakToday(ownDone: true, partnerDone: true, deadline: nil, isResting: true)
        }
        let ownDone = currentUserContributedToday
        let partnerDone = partnerContributedToday
        let isSaveDay = restorableCount > 0 && (saveDeadline.map { $0 > now } ?? false)
        let end = isSaveDay ? saveDeadline : (currentCount > 0 ? endsAt : nil)
        let deadline = ownDone && partnerDone ? nil : end.flatMap { $0 > now ? $0 : nil }
        return StreakToday(ownDone: ownDone, partnerDone: partnerDone, deadline: deadline, isResting: false)
    }
}

nonisolated enum StreakEntryDestination: Equatable, Sendable {
    case detail
    case restore
    case milestone(Int)
}
