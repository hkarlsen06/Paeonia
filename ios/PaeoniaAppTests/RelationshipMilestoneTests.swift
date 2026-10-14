import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the contextual milestone schedule shown on the Home tab countdown card. The
/// kind of milestone has to change as a relationship ages — months while it's new,
/// then anniversaries and round day counts — so these pin down which milestone is
/// "next" at each stage and how many days are left.
struct RelationshipMilestoneTests {
    // A fixed UTC calendar keeps the day math deterministic (no DST, no locale drift).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }()

    private func calculator() -> RelationshipMilestoneCalculator {
        RelationshipMilestoneCalculator(calendar: calendar)
    }

    private func day(_ iso: String) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return try #require(calendar.date(from: components))
    }

    @Test func brandNewCoupleCountsDownToFirstMonth() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-01-08"))

        #expect(milestone?.kind == .firstMonth)
        #expect(milestone?.daysRemaining == 31)
    }

    @Test func afterFirstMonthCountsDownToTwoMonths() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-02-09"))

        #expect(milestone?.kind == .months(2))
        #expect(milestone?.daysRemaining == 27)
    }

    @Test func threeMonthMarkUsesMonthsKindNotSpecialCase() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-03-20"))

        #expect(milestone?.kind == .months(3))
        #expect(milestone?.daysRemaining == 19)
    }

    @Test func hundredDaysWinsWhenItIsTheSoonestMarker() throws {
        // Past the 3-month mark (2026-04-08) but before the 4-month mark (2026-05-08),
        // the 100-days marker (2026-04-18) is the next thing to count down to.
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-04-09"))

        #expect(milestone?.kind == .days(100))
        #expect(milestone?.daysRemaining == 9)
    }

    @Test func sixMonthsIsCalledHalfAYear() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-06-20"))

        #expect(milestone?.kind == .halfYear)
        #expect(milestone?.daysRemaining == 18)
    }

    @Test func afterElevenMonthsCountsDownToFirstAnniversary() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-12-20"))

        #expect(milestone?.kind == .firstAnniversary)
        #expect(milestone?.daysRemaining == 19)
    }

    @Test func fiveHundredDaysFillsTheGapBetweenFirstAndSecondAnniversary() throws {
        // Months no longer apply; between year one and year two the 500-days marker
        // (2027-05-23) arrives before the second anniversary (2028-01-08).
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2027-04-01"))

        #expect(milestone?.kind == .days(500))
        #expect(milestone?.daysRemaining == 52)
    }

    @Test func olderCoupleCountsDownToNextAnniversary() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2030-06-01"))

        #expect(milestone?.kind == .years(5))
    }

    @Test func onTheMilestoneDayDaysRemainingIsZero() throws {
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2026-02-08"))

        #expect(milestone?.kind == .firstMonth)
        #expect(milestone?.daysRemaining == 0)
    }

    @Test func thousandDaysMarkerIsReachableAfterTheEarlyMarkers() throws {
        // 1,000 days from 2026-01-08 lands on 2028-10-04; just before it, with the
        // 500-days marker already passed, it is the next day-count milestone.
        let milestone = calculator().nextMilestone(startedOn: "2026-01-08", now: try day("2028-10-01"))

        #expect(milestone?.kind == .days(1_000))
        #expect(milestone?.daysRemaining == 3)
    }

    @Test func unparseableStartDateHasNoMilestone() throws {
        #expect(calculator().nextMilestone(startedOn: "not-a-date", now: try day("2026-06-01")) == nil)
    }

    // MARK: - Upcoming milestone timeline

    @Test func upcomingMilestonesListsTheScheduleInOrder() throws {
        // The timeline sheet shows the next few milestones; the 100-days marker has
        // to slot between the monthly markers by date, not be appended at the end.
        let milestones = calculator().upcomingMilestones(
            startedOn: "2026-01-08",
            now: try day("2026-01-08"),
            limit: 6
        )

        #expect(milestones.map(\.kind) == [
            .firstMonth, .months(2), .months(3), .days(100), .months(4), .months(5)
        ])
        #expect(milestones.map(\.daysRemaining) == [31, 59, 90, 100, 120, 151])
    }

    @Test func upcomingMilestonesCountDaysFromTodayNotFromEachOther() throws {
        // now sits between milestones; every entry's daysRemaining is still measured
        // from today so a list reads "in 9 days / in 29 days / …".
        let milestones = calculator().upcomingMilestones(
            startedOn: "2026-01-08",
            now: try day("2026-04-09"),
            limit: 2
        )

        #expect(milestones.map(\.kind) == [.days(100), .months(4)])
        #expect(milestones.map(\.daysRemaining) == [9, 29])
    }

    @Test func upcomingMilestonesStartWithTodayOnAMilestoneDay() throws {
        let milestones = calculator().upcomingMilestones(
            startedOn: "2026-01-08",
            now: try day("2026-02-08"),
            limit: 2
        )

        #expect(milestones.first?.kind == .firstMonth)
        #expect(milestones.first?.daysRemaining == 0)
        #expect(milestones.map(\.kind) == [.firstMonth, .months(2)])
    }

    @Test func upcomingMilestonesForUnparseableStartDateIsEmpty() throws {
        #expect(calculator().upcomingMilestones(
            startedOn: "not-a-date",
            now: try day("2026-06-01"),
            limit: 5
        ).isEmpty)
    }

    // MARK: - Past milestones

    @Test func pastMilestonesListsTheMostRecentHistoryInOrder() throws {
        // Between the 100-days marker (2026-04-18) and the 4-month mark (2026-05-08),
        // history is everything up to and including 100 days, oldest first, capped
        // at the limit. daysRemaining is negative: days since the milestone.
        let milestones = calculator().pastMilestones(
            startedOn: "2026-01-08",
            now: try day("2026-04-20"),
            limit: 3
        )

        #expect(milestones.map(\.kind) == [.months(2), .months(3), .days(100)])
        #expect(milestones.map(\.daysRemaining) == [-43, -12, -2])
    }

    @Test func pastMilestonesExcludesAMilestoneLandingToday() throws {
        // On the 100-days day itself the marker belongs to upcoming (as "Today"),
        // not to history.
        let milestones = calculator().pastMilestones(
            startedOn: "2026-01-08",
            now: try day("2026-04-18"),
            limit: 10
        )

        #expect(milestones.map(\.kind) == [.firstMonth, .months(2), .months(3)])
    }

    @Test func pastMilestonesIsEmptyForABrandNewCouple() throws {
        #expect(calculator().pastMilestones(
            startedOn: "2026-01-08",
            now: try day("2026-01-08"),
            limit: 5
        ).isEmpty)
    }

    @Test func pastMilestonesForUnparseableStartDateIsEmpty() throws {
        #expect(calculator().pastMilestones(
            startedOn: "not-a-date",
            now: try day("2026-06-01"),
            limit: 5
        ).isEmpty)
    }

    // MARK: - Days together

    @Test func daysTogetherCountsWholeDaysFromTheStartDate() throws {
        #expect(calculator().daysTogether(startedOn: "2026-01-08", now: try day("2026-04-18")) == 100)
    }

    @Test func daysTogetherIsZeroOnTheDayTheCoupleGotTogether() throws {
        #expect(calculator().daysTogether(startedOn: "2026-01-08", now: try day("2026-01-08")) == 0)
    }

    @Test func daysTogetherForUnparseableStartDateIsNil() throws {
        #expect(calculator().daysTogether(startedOn: "not-a-date", now: try day("2026-06-01")) == nil)
    }

    @Test func isoStartDateIsNotReinterpretedThroughPreferredCalendar() throws {
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = calendar.timeZone
        let calculator = RelationshipMilestoneCalculator(calendar: buddhistCalendar)

        let milestone = calculator.nextMilestone(
            startedOn: "2026-01-08",
            now: try day("2026-01-08")
        )

        #expect(milestone?.kind == .firstMonth)
        #expect(milestone?.daysRemaining == 31)
    }
}

/// Day boundaries, clock changes, and time zones for the milestone math. Every test
/// builds its own Gregorian calendar in a named zone and makes `now` from local
/// wall-clock components, so the results do not depend on the zone of the machine
/// running them. Each partner counts on their own wall calendar, so a different
/// zone can give a different answer for the same instant.
struct RelationshipMilestoneCalendarTests {
    /// A Gregorian calendar fixed to one named time zone.
    private struct Zone {
        let calendar: Calendar

        init(_ identifier: String) throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: identifier))
            self.calendar = calendar
        }

        var calculator: RelationshipMilestoneCalculator {
            RelationshipMilestoneCalculator(calendar: calendar)
        }

        /// The instant of a local wall-clock time on a `yyyy-MM-dd` day. Noon unless given.
        func instant(_ iso: String, hour: Int = 12, minute: Int = 0, second: Int = 0) throws -> Date {
            let parts = iso.split(separator: "-").compactMap { Int($0) }
            let components = DateComponents(
                year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute, second: second
            )
            return try #require(calendar.date(from: components))
        }

        /// The local `yyyy-MM-dd` calendar day an instant falls on.
        func isoDay(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    // MARK: - Day boundary

    @Test func countdownFlipsAtLocalMidnight() throws {
        let oslo = try Zone("Europe/Oslo")
        let lastSecond = oslo.calculator.nextMilestone(
            startedOn: "2026-01-08",
            now: try oslo.instant("2026-02-07", hour: 23, minute: 59, second: 59)
        )
        let firstSecond = oslo.calculator.nextMilestone(
            startedOn: "2026-01-08",
            now: try oslo.instant("2026-02-08", hour: 0, minute: 0, second: 1)
        )

        #expect(lastSecond?.kind == .firstMonth)
        #expect(lastSecond?.daysRemaining == 1)
        #expect(firstSecond?.kind == .firstMonth)
        #expect(firstSecond?.daysRemaining == 0)
        #expect(lastSecond?.date == firstSecond?.date)
    }

    // MARK: - Clock changes

    private struct ClockChangeScenario {
        let zone: String
        let startedOn: String
        /// The local day "now" falls on, at noon.
        let today: String
        let kind: RelationshipMilestone.Kind
        let milestoneDay: String
        let daysRemaining: Int
    }

    /// Oslo changes clocks on 2026-03-29 (a 23-hour day) and 2026-10-25 (25 hours).
    /// New York changes on 2026-03-08 (23 hours) and 2026-11-01 (25 hours). Every
    /// scenario counts across one of those days. The spring ones would come out a
    /// day short if the code divided elapsed hours by 24 instead of counting dates.
    private static let clockChangeScenarios = [
        ClockChangeScenario(
            zone: "Europe/Oslo", startedOn: "2026-01-30", today: "2026-03-28",
            kind: .months(2), milestoneDay: "2026-03-30", daysRemaining: 2
        ),
        ClockChangeScenario(
            zone: "Europe/Oslo", startedOn: "2026-01-30", today: "2026-03-29",
            kind: .months(2), milestoneDay: "2026-03-30", daysRemaining: 1
        ),
        ClockChangeScenario(
            zone: "Europe/Oslo", startedOn: "2026-09-26", today: "2026-10-24",
            kind: .firstMonth, milestoneDay: "2026-10-26", daysRemaining: 2
        ),
        ClockChangeScenario(
            zone: "Europe/Oslo", startedOn: "2026-09-26", today: "2026-10-25",
            kind: .firstMonth, milestoneDay: "2026-10-26", daysRemaining: 1
        ),
        ClockChangeScenario(
            zone: "America/New_York", startedOn: "2026-01-10", today: "2026-03-07",
            kind: .months(2), milestoneDay: "2026-03-10", daysRemaining: 3
        ),
        ClockChangeScenario(
            zone: "America/New_York", startedOn: "2026-01-10", today: "2026-03-08",
            kind: .months(2), milestoneDay: "2026-03-10", daysRemaining: 2
        ),
        ClockChangeScenario(
            zone: "America/New_York", startedOn: "2026-10-02", today: "2026-10-31",
            kind: .firstMonth, milestoneDay: "2026-11-02", daysRemaining: 2
        ),
        ClockChangeScenario(
            zone: "America/New_York", startedOn: "2026-10-02", today: "2026-11-01",
            kind: .firstMonth, milestoneDay: "2026-11-02", daysRemaining: 1
        )
    ]

    @Test func countdownCountsCalendarDaysAcrossClockChanges() throws {
        for scenario in Self.clockChangeScenarios {
            let zone = try Zone(scenario.zone)
            let label: Comment = "\(scenario.zone) from \(scenario.startedOn) on \(scenario.today)"
            let now = try zone.instant(scenario.today)
            let milestone = try #require(
                zone.calculator.nextMilestone(startedOn: scenario.startedOn, now: now),
                label
            )

            #expect(milestone.kind == scenario.kind, label)
            #expect(zone.isoDay(milestone.date) == scenario.milestoneDay, label)
            #expect(milestone.daysRemaining == scenario.daysRemaining, label)
        }
    }

    private struct DaysTogetherScenario {
        let zone: String
        let startedOn: String
        let today: String
        let days: Int
    }

    @Test func daysTogetherCountsCalendarDaysAcrossClockChanges() throws {
        let scenarios = [
            DaysTogetherScenario(zone: "Europe/Oslo", startedOn: "2026-03-01", today: "2026-03-31", days: 30),
            DaysTogetherScenario(zone: "Europe/Oslo", startedOn: "2026-03-29", today: "2026-03-30", days: 1),
            DaysTogetherScenario(zone: "Europe/Oslo", startedOn: "2026-10-01", today: "2026-10-31", days: 30),
            DaysTogetherScenario(zone: "Europe/Oslo", startedOn: "2026-10-25", today: "2026-10-26", days: 1),
            DaysTogetherScenario(zone: "America/New_York", startedOn: "2026-03-07", today: "2026-03-09", days: 2),
            DaysTogetherScenario(zone: "America/New_York", startedOn: "2026-10-31", today: "2026-11-02", days: 2)
        ]

        for scenario in scenarios {
            let zone = try Zone(scenario.zone)
            let label: Comment = "\(scenario.zone) from \(scenario.startedOn) to \(scenario.today)"
            let now = try zone.instant(scenario.today)

            #expect(zone.calculator.daysTogether(startedOn: scenario.startedOn, now: now) == scenario.days, label)
        }
    }

    @Test func milestoneOnADayWithoutMidnightStillLandsOnThatDay() throws {
        // Brazil skipped 2018-11-04 00:00 (clocks went straight to 01:00), so the
        // first month of a couple that started 2018-10-04 has no midnight to land on.
        let saoPaulo = try Zone("America/Sao_Paulo")
        let now = try saoPaulo.instant("2018-11-04")

        let milestone = saoPaulo.calculator.nextMilestone(startedOn: "2018-10-04", now: now)

        #expect(milestone?.kind == .firstMonth)
        #expect(milestone?.daysRemaining == 0)
        #expect(milestone.map { saoPaulo.isoDay($0.date) } == "2018-11-04")
        #expect(saoPaulo.calculator.daysTogether(startedOn: "2018-10-04", now: now) == 31)
    }

    // MARK: - Time zones

    @Test func theSameInstantIsADifferentDayInEachPartnersZone() throws {
        // 23:30 UTC on 2026-02-07 is already 2026-02-08 in Oslo and still the 7th in
        // Los Angeles. Each partner counts on their own wall calendar.
        let instant = try Zone("UTC").instant("2026-02-07", hour: 23, minute: 30)
        let oslo = try Zone("Europe/Oslo")
        let losAngeles = try Zone("America/Los_Angeles")

        let inOslo = oslo.calculator.nextMilestone(startedOn: "2026-01-08", now: instant)
        let inLosAngeles = losAngeles.calculator.nextMilestone(startedOn: "2026-01-08", now: instant)

        #expect(inOslo?.kind == .firstMonth)
        #expect(inOslo?.daysRemaining == 0)
        #expect(inLosAngeles?.kind == .firstMonth)
        #expect(inLosAngeles?.daysRemaining == 1)
    }

    // MARK: - Calendar edges

    @Test func leapDayStartHasItsAnniversaryOnFebruary28ThenOnLeapDays() throws {
        let oslo = try Zone("Europe/Oslo")

        let first = oslo.calculator.nextMilestone(startedOn: "2024-02-29", now: try oslo.instant("2025-02-28"))
        let fourth = oslo.calculator.nextMilestone(startedOn: "2024-02-29", now: try oslo.instant("2028-02-28"))

        #expect(first?.kind == .firstAnniversary)
        #expect(first.map { oslo.isoDay($0.date) } == "2025-02-28")
        #expect(first?.daysRemaining == 0)
        #expect(fourth?.kind == .years(4))
        #expect(fourth.map { oslo.isoDay($0.date) } == "2028-02-29")
        #expect(fourth?.daysRemaining == 1)
    }

    @Test func monthEndStartClampsShortMonthsButNotLongOnes() throws {
        let oslo = try Zone("Europe/Oslo")

        let milestones = oslo.calculator.upcomingMilestones(
            startedOn: "2026-01-31",
            now: try oslo.instant("2026-01-31"),
            limit: 3
        )

        #expect(milestones.map(\.kind) == [.firstMonth, .months(2), .months(3)])
        #expect(milestones.map { oslo.isoDay($0.date) } == ["2026-02-28", "2026-03-31", "2026-04-30"])
        #expect(milestones.map(\.daysRemaining) == [28, 59, 89])
    }

    @Test func upcomingMilestonesNeverRepeatADateAndAlwaysMoveForward() throws {
        let oslo = try Zone("Europe/Oslo")
        let now = try oslo.instant("2026-06-20")

        for startedOn in ["2023-06-15", "2023-02-28", "2023-01-31", "2024-02-29"] {
            let milestones = oslo.calculator.upcomingMilestones(startedOn: startedOn, now: now, limit: 12)
            let pairs = Array(zip(milestones, milestones.dropFirst()))
            let label: Comment = "started \(startedOn)"

            #expect(milestones.count == 12, label)
            #expect(pairs.allSatisfy { $0.date < $1.date }, label)
            #expect(pairs.allSatisfy { $0.daysRemaining < $1.daysRemaining }, label)
            #expect((milestones.first?.daysRemaining ?? -1) >= 0, label)
        }
    }
}
