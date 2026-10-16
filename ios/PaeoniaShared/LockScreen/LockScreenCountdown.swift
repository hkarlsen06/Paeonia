import Foundation

/// The "Next countdown" widget: the first countdown that is today or later.
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
    /// From the day the countdown was made (0) to the start of its target day (1).
    let progress: Double

    /// Picks the first countdown whose target day is today or later on the device
    /// calendar. The server's list can still hold yesterday's countdown.
    static func next(
        in countdowns: [LockScreenSnapshot.Countdown],
        now: Date,
        calendar: Calendar
    ) -> Self? {
        let today = LockScreenCalendarDate(containing: now, in: calendar)
        guard let countdown = countdowns.first(where: { $0.targetDate >= today }) else {
            return nil
        }
        return Self(
            title: countdown.title,
            remaining: Remaining(days: today.days(until: countdown.targetDate)),
            progress: progress(of: countdown, now: now, calendar: calendar)
        )
    }

    private static func progress(
        of countdown: LockScreenSnapshot.Countdown,
        now: Date,
        calendar: Calendar
    ) -> Double {
        guard let target = countdown.targetDate.startOfDay(in: calendar) else { return 0 }
        let total = target.timeIntervalSince(countdown.createdAt)
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(countdown.createdAt)
        return min(1, max(0, elapsed / total))
    }
}
