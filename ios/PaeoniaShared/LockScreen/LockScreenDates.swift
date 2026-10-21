import Foundation

/// One date the Home Screen countdown widget can show: a countdown or a birthday,
/// with the day it falls on next.
nonisolated struct LockScreenDateItem: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case countdown(title: String)
        /// `isMine` is true for the person who owns this phone.
        case birthday(isMine: Bool)
    }

    /// Stable across refreshes, so a widget keeps showing the date it was set to.
    let id: String
    let kind: Kind
    /// The day it falls on. A yearly countdown or a birthday is always today or later.
    /// A one-off countdown keeps its own day, which can be yesterday on a phone behind the server.
    let date: LockScreenCalendarDate
    let daysRemaining: Int
    let repeatsYearly: Bool
    /// Where the countdown widget's progress bar starts. Nil for a birthday.
    let progressStart: ProgressStart?

    enum ProgressStart: Equatable, Sendable {
        /// A one-off countdown, or a yearly one in its first year, runs from the moment it was made.
        case created(Date)
        /// A yearly countdown after its first year runs from the start of the occurrence before.
        case day(LockScreenCalendarDate)
    }

    var remaining: LockScreenCountdown.Remaining { .init(days: daysRemaining) }

    /// Breaks ties on the same day the way the Home tile does: birthdays before countdowns.
    fileprivate var sortRank: Int {
        switch kind {
        case .birthday: 0
        case .countdown: 1
        }
    }
}

/// The dates behind the Home Screen countdown widget: what the person can pick,
/// and which one a widget shows. Pure, so it is unit tested.
nonisolated enum LockScreenDates {
    /// The id of the "next one" choice, which always shows the soonest date.
    static let nextID = "next"

    static func countdownID(_ id: String) -> String { "countdown:\(id)" }
    static func birthdayID(isMine: Bool) -> String { isMine ? "birthday:me" : "birthday:partner" }

    /// Dates that are today or later, soonest first. Yearly countdowns and
    /// birthdays show their next occurrence. A one-off countdown that passed
    /// before today is left out.
    static func items(in dates: LockScreenSnapshot.Dates, today: LockScreenCalendarDate) -> [LockScreenDateItem] {
        let countdowns = dates.countdowns.compactMap { countdown -> LockScreenDateItem? in
            let date = countdown.repeatsYearly
                ? countdown.targetDate.nextYearlyOccurrence(onOrAfter: today)
                : countdown.targetDate
            guard date >= today else { return nil }
            let progressStart: LockScreenDateItem.ProgressStart = date == countdown.targetDate
                ? .created(countdown.createdAt)
                : .day(date.moved(toYear: date.year - 1))
            return LockScreenDateItem(
                id: countdownID(countdown.id),
                kind: .countdown(title: countdown.title),
                date: date,
                daysRemaining: today.days(until: date),
                repeatsYearly: countdown.repeatsYearly,
                progressStart: progressStart
            )
        }
        let birthdays = dates.birthdays.map { birthday in
            let date = birthday.birthday.nextYearlyOccurrence(onOrAfter: today)
            return LockScreenDateItem(
                id: birthdayID(isMine: birthday.isMine),
                kind: .birthday(isMine: birthday.isMine),
                date: date,
                daysRemaining: today.days(until: date),
                repeatsYearly: true,
                progressStart: nil
            )
        }
        return (countdowns + birthdays).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.sortRank != $1.sortRank { return $0.sortRank < $1.sortRank }
            return $0.id < $1.id
        }
    }

    /// The date a widget shows. "Next one", no choice, or a date that was deleted
    /// since the widget was set up all show the soonest date.
    static func selected(id: String?, in items: [LockScreenDateItem]) -> LockScreenDateItem? {
        if let id, id != nextID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }

    /// The dates after `shown`, soonest first, for the medium widget's list.
    static func comingUp(
        after shown: LockScreenDateItem,
        in items: [LockScreenDateItem],
        limit: Int
    ) -> [LockScreenDateItem] {
        Array(items.filter { $0.id != shown.id }.prefix(limit))
    }
}
