import Foundation

/// The next meaningful date a couple is counting down to, derived from the day they
/// started (`couples.started_on`).
///
/// The *kind* of milestone changes with how long they've been together: monthly
/// markers while the relationship is new, then yearly anniversaries and the round
/// day counts that fall in between. That's what keeps the Us-tab card feeling
/// current instead of stuck on a single hard-coded "6-month" value — for a brand new
/// couple it counts down to their first month, and for a couple of several years it
/// counts down to their next anniversary or their 1,000-days mark.
nonisolated struct RelationshipMilestone: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The first whole month together.
        case firstMonth
        /// A monthly marker inside the first year (2–5 and 7–11 months).
        case months(Int)
        /// Six months — called out as "half a year" rather than "6 months".
        case halfYear
        /// The first yearly anniversary.
        case firstAnniversary
        /// A later yearly anniversary (2 years and beyond).
        case years(Int)
        /// A round day-count marker (100, 500, 1,000, 2,000, …).
        case days(Int)
    }

    let kind: Kind
    /// Start-of-day for the milestone, in the calendar used to compute it.
    let date: Date
    /// Whole calendar days from "today" to the milestone date. `0` on the day itself.
    let daysRemaining: Int
}

extension RelationshipMilestone.Kind {
    /// Tie-break weight when two milestone families land on the same calendar day, so
    /// a shared date reads as the anniversary rather than an incidental day count.
    /// `nonisolated` so the pure calculator can read it off the main actor.
    nonisolated var tieBreakPriority: Int {
        switch self {
        case .firstAnniversary, .years: 3
        case .halfYear: 2
        case .firstMonth, .months: 1
        case .days: 0
        }
    }
}

/// Pure milestone math. Given the day a couple started and "now", it returns the
/// single soonest upcoming milestone. Kept free of SwiftUI so the schedule is unit
/// tested directly.
nonisolated struct RelationshipMilestoneCalculator {
    /// Round day counts worth celebrating before the every-1,000 cadence takes over.
    /// 100 and 500 fill the long stretches the monthly/yearly markers leave open
    /// (e.g. between the first and second anniversary).
    private static let earlyDayMilestones = [100, 500]
    /// After the early markers, day-count milestones land on each multiple of this.
    private static let dayMilestoneStride = 1000

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The next milestone for an `yyyy-MM-dd` start date, or `nil` when it can't be
    /// parsed. The date is read in the calculator's calendar so the day count matches
    /// what a person would tally on their own wall calendar.
    func nextMilestone(startedOn rawDate: String, now: Date = Date()) -> RelationshipMilestone? {
        guard let start = startOfDay(fromISODate: rawDate) else { return nil }
        return nextMilestone(start: start, now: now)
    }

    func nextMilestone(start: Date, now: Date = Date()) -> RelationshipMilestone? {
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)

        let candidates = [
            nextMonthlyMilestone(startDay: startDay, today: today),
            nextYearlyMilestone(startDay: startDay, today: today),
            nextDayCountMilestone(startDay: startDay, today: today)
        ].compactMap { $0 }

        // Soonest date wins; on a tie the weightier kind wins.
        return candidates.min { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.kind.tieBreakPriority > rhs.kind.tieBreakPriority
        }
    }

    // MARK: - Milestone families

    private func nextMonthlyMilestone(startDay: Date, today: Date) -> RelationshipMilestone? {
        // Only the first year is measured in months; after that yearly anniversaries
        // and day counts carry the countdown. Dates grow with `months`, so the first
        // one that has not passed is the soonest.
        for months in 1...11 {
            guard let date = calendar.date(byAdding: .month, value: months, to: startDay),
                  date >= today else { continue }
            let kind: RelationshipMilestone.Kind = switch months {
            case 1: .firstMonth
            case 6: .halfYear
            default: .months(months)
            }
            return milestone(kind: kind, date: date, today: today)
        }
        return nil
    }

    private func nextYearlyMilestone(startDay: Date, today: Date) -> RelationshipMilestone? {
        // Start from the number of full years already elapsed so old couples don't
        // loop up from year 1. A short bounded search absorbs leap-day boundaries.
        let elapsedYears = calendar.dateComponents([.year], from: startDay, to: today).year ?? 0
        var years = max(1, elapsedYears)
        for _ in 0..<4 {
            if let date = calendar.date(byAdding: .year, value: years, to: startDay), date >= today {
                let kind: RelationshipMilestone.Kind = years == 1 ? .firstAnniversary : .years(years)
                return milestone(kind: kind, date: date, today: today)
            }
            years += 1
        }
        return nil
    }

    private func nextDayCountMilestone(startDay: Date, today: Date) -> RelationshipMilestone? {
        let elapsedDays = days(from: startDay, to: today)
        let target = nextDayCountThreshold(elapsedDays: elapsedDays)
        guard let date = calendar.date(byAdding: .day, value: target, to: startDay) else { return nil }
        return milestone(kind: .days(target), date: date, today: today)
    }

    private func nextDayCountThreshold(elapsedDays: Int) -> Int {
        for milestone in Self.earlyDayMilestones where milestone >= elapsedDays {
            return milestone
        }
        // The smallest multiple of the stride that is today or still ahead.
        let stride = Self.dayMilestoneStride
        var threshold = max(1, Int((Double(elapsedDays) / Double(stride)).rounded(.up))) * stride
        if threshold < elapsedDays { threshold += stride }
        return threshold
    }

    // MARK: - Helpers

    private func milestone(
        kind: RelationshipMilestone.Kind,
        date: Date,
        today: Date
    ) -> RelationshipMilestone {
        RelationshipMilestone(kind: kind, date: date, daysRemaining: days(from: today, to: date))
    }

    private func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    private func startOfDay(fromISODate rawDate: String) -> Date? {
        let parts = rawDate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }
}
