import Foundation

/// The "Next countdown" Lock Screen widget: the first countdown that is today or later.
nonisolated struct LockScreenCountdown: Equatable, Sendable {
    enum Remaining: Equatable, Sendable {
        case today
        case tomorrow
        case days(Int)

        init(days: Int) {
            switch days {
            case ...0: self = .today
            case 1: self = .tomorrow
            default: self = .days(days)
            }
        }
    }

    let title: String
    let remaining: Remaining
    /// From the start of the bar to the start of the target day (1). A one-off
    /// countdown starts when it was made. A yearly one starts at the occurrence before.
    let progress: Double

    /// Picks the soonest countdown that falls today or later on the device calendar.
    /// It works from the stored dates, like the Home Screen widget, so a yearly
    /// countdown moves on to next year at midnight without a new fetch. Birthdays are not countdowns here.
    static func next(
        in dates: LockScreenSnapshot.Dates,
        now: Date,
        calendar: Calendar
    ) -> Self? {
        let today = LockScreenCalendarDate(containing: now, in: calendar)
        for item in LockScreenDates.items(in: dates, today: today) {
            guard case let .countdown(title) = item.kind, let start = item.progressStart else { continue }
            return Self(
                title: title,
                remaining: item.remaining,
                progress: progress(from: start, to: item.date, now: now, calendar: calendar)
            )
        }
        return nil
    }

    private static func progress(
        from start: LockScreenDateItem.ProgressStart,
        to targetDate: LockScreenCalendarDate,
        now: Date,
        calendar: Calendar
    ) -> Double {
        let started: Date?
        switch start {
        case let .created(date): started = date
        case let .day(day): started = day.startOfDay(in: calendar)
        }
        guard let started, let target = targetDate.startOfDay(in: calendar) else { return 0 }
        let total = target.timeIntervalSince(started)
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(started)
        return min(1, max(0, elapsed / total))
    }
}
