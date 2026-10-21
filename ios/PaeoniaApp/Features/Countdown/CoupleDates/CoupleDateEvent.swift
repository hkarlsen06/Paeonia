import Foundation

/// One row of the milestones timeline and the Home tile: a relationship milestone, a
/// countdown the couple added, or a partner's birthday.
nonisolated struct CoupleDateEvent: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case milestone(RelationshipMilestone.Kind)
        case countdown(CustomCountdown)
        case birthday(userID: UUID)
    }

    let kind: Kind
    /// Start of the day, in the calendar used to compute it.
    let date: Date
    /// Whole calendar days from today. `0` on the day, negative once it has passed.
    let daysRemaining: Int

    var id: String {
        switch kind {
        case .milestone:
            "milestone-\(date.timeIntervalSinceReferenceDate)"
        case let .countdown(countdown):
            "countdown-\(countdown.id.uuidString)"
        case let .birthday(userID):
            "birthday-\(userID.uuidString)-\(date.timeIntervalSinceReferenceDate)"
        }
    }

    /// Breaks ties on the same day, so the order doesn't jump between renders.
    fileprivate var sortRank: Int {
        switch kind {
        case .milestone: 0
        case .birthday: 1
        case .countdown: 2
        }
    }

    fileprivate static func chronological(_ lhs: CoupleDateEvent, _ rhs: CoupleDateEvent) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
        return lhs.id < rhs.id
    }
}

/// Pure merge of the milestones from the start date with the couple's own countdowns and
/// birthdays. Free of SwiftUI so it is unit tested directly.
nonisolated struct CoupleDateTimeline {
    private let milestones: RelationshipMilestoneCalculator

    init(calendar: Calendar = .current) {
        milestones = RelationshipMilestoneCalculator(calendar: calendar)
    }

    private var calendar: Calendar {
        milestones.calendar
    }

    /// The soonest event that is today or later, for the Home tile.
    func next(startedOn: String?, dates: CoupleDates, now: Date = Date()) -> CoupleDateEvent? {
        upcoming(startedOn: startedOn, dates: dates, now: now, milestoneLimit: 1).first
    }

    /// Events today or later, soonest first: the next `milestoneLimit` milestones, every
    /// countdown that hasn't passed, and each partner's next birthday.
    func upcoming(
        startedOn: String?,
        dates: CoupleDates,
        now: Date = Date(),
        milestoneLimit: Int
    ) -> [CoupleDateEvent] {
        let today = calendar.startOfDay(for: now)
        let milestoneEvents = startedOn
            .map { milestones.upcomingMilestones(startedOn: $0, now: now, limit: milestoneLimit) } ?? []
        let countdownEvents = countdownEvents(dates, today: today).filter { $0.daysRemaining >= 0 }
        let birthdayEvents = dates.birthdays.compactMap { userID, birthday in
            nextBirthday(userID: userID, birthday: birthday, today: today)
        }
        return (milestoneEvents.map(Self.event) + countdownEvents + birthdayEvents)
            .sorted(by: CoupleDateEvent.chronological)
    }

    /// The last `limit` events before today, oldest first: past milestones and countdowns
    /// whose day has gone. Birthdays and yearly countdowns come back every year, so only
    /// the next one shows.
    func past(startedOn: String?, dates: CoupleDates, now: Date = Date(), limit: Int) -> [CoupleDateEvent] {
        let today = calendar.startOfDay(for: now)
        let milestoneEvents = startedOn
            .map { milestones.pastMilestones(startedOn: $0, now: now, limit: limit) } ?? []
        let countdownEvents = countdownEvents(dates, today: today).filter { $0.daysRemaining < 0 }
        return Array(
            (milestoneEvents.map(Self.event) + countdownEvents)
                .sorted(by: CoupleDateEvent.chronological)
                .suffix(limit)
        )
    }

    /// The next time `birthday` (`yyyy-MM-dd`) comes around, today included. A 29 February
    /// birthday falls on 28 February in other years.
    func nextBirthday(userID: UUID, birthday: String, today: Date) -> CoupleDateEvent? {
        yearlyEvent(.birthday(userID: userID), isoDate: birthday, today: today)
    }

    /// An event for the next time a date that repeats every year comes around, today
    /// included. A date still ahead is its own first occurrence. The rule is
    /// `LockScreenCalendarDate.nextYearlyOccurrence`, shared with the widgets and mirrored
    /// by `backend/convex/lib/coupleDates.ts`, so birthdays and yearly countdowns agree
    /// everywhere, 29 February included.
    private func yearlyEvent(_ kind: CoupleDateEvent.Kind, isoDate: String, today: Date) -> CoupleDateEvent? {
        guard let original = LockScreenCalendarDate(isoDate),
              let date = original
                  .nextYearlyOccurrence(onOrAfter: LockScreenCalendarDate(containing: today, in: calendar))
                  .startOfDay(in: calendar)
        else { return nil }
        return CoupleDateEvent(kind: kind, date: date, daysRemaining: milestones.days(from: today, to: date))
    }

    /// A countdown that repeats every year is never past: it shows its next occurrence.
    private func countdownEvents(_ dates: CoupleDates, today: Date) -> [CoupleDateEvent] {
        dates.countdowns.compactMap { countdown in
            if countdown.repeatsYearly {
                return yearlyEvent(.countdown(countdown), isoDate: countdown.targetDate, today: today)
            }
            guard let date = milestones.startOfDay(fromISODate: countdown.targetDate) else { return nil }
            return CoupleDateEvent(
                kind: .countdown(countdown),
                date: date,
                daysRemaining: milestones.days(from: today, to: date)
            )
        }
    }

    private static func event(_ milestone: RelationshipMilestone) -> CoupleDateEvent {
        CoupleDateEvent(kind: .milestone(milestone.kind), date: milestone.date, daysRemaining: milestone.daysRemaining)
    }
}
