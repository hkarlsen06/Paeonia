import Foundation

/// The "Days together" widget: the day count and how far it is toward the next milestone.
nonisolated struct LockScreenDaysTogether: Equatable, Sendable {
    /// Milestones before the first year ends and between the early years.
    /// After 1000 days only whole years count.
    static let fixedMilestones = [100, 200, 500, 1_000]
    // ponytail: a year is 365 days, so anniversaries drift by a day per leap year.
    // Use real anniversary dates if that ever shows.
    static let daysPerYear = 365

    let days: Int
    let previousMilestone: Int
    let nextMilestone: Int

    /// 0 right after a milestone, 1 on the day before the next one.
    var progress: Double {
        Double(days - previousMilestone) / Double(nextMilestone - previousMilestone)
    }

    init(days: Int) {
        let days = max(0, days)
        self.days = days
        let thisYear = days / Self.daysPerYear * Self.daysPerYear
        previousMilestone = (Self.fixedMilestones.filter { $0 <= days } + [thisYear]).max() ?? 0
        nextMilestone = (Self.fixedMilestones.filter { $0 > days } + [thisYear + Self.daysPerYear]).min()
            ?? thisYear + Self.daysPerYear
    }

    /// Whole calendar days from the start day to today in `calendar`. It is 0 on
    /// the start day itself, and nil when the couple has not set a start date.
    init?(startedOn: LockScreenCalendarDate?, now: Date, calendar: Calendar) {
        guard let startedOn else { return nil }
        let today = LockScreenCalendarDate(containing: now, in: calendar)
        self.init(days: startedOn.days(until: today))
    }
}
