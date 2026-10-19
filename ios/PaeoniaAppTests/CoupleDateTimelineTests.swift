import Foundation
import Testing
@testable import PaeoniaApp

/// Covers how the couple's own countdowns and birthdays merge with the milestones on
/// the Home tile and the milestones timeline, and how queued writes lay over the
/// server's copy.
@MainActor
struct CoupleDateTimelineTests {
    // A fixed UTC calendar keeps the day math deterministic (no DST, no locale drift).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }()

    private let me = UUID()
    private let partner = UUID()

    private func timeline() -> CoupleDateTimeline {
        CoupleDateTimeline(calendar: calendar)
    }

    private func day(_ iso: String) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return try #require(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])))
    }

    private func countdown(_ title: String, _ date: String) -> CustomCountdown {
        CustomCountdown(id: UUID(), title: title, targetDate: date)
    }

    @Test func aCountdownBeforeTheNextMilestoneTakesTheHomeTile() throws {
        let trip = countdown("Trip", "2026-01-20")
        let next = timeline().next(
            startedOn: "2026-01-08",
            dates: CoupleDates(countdowns: [trip]),
            now: try day("2026-01-10")
        )

        #expect(next?.kind == .countdown(trip))
        #expect(next?.daysRemaining == 10)
    }

    @Test func theMilestoneKeepsTheTileWhenItComesFirst() throws {
        let next = timeline().next(
            startedOn: "2026-01-08",
            dates: CoupleDates(countdowns: [countdown("Trip", "2026-03-01")]),
            now: try day("2026-01-10")
        )

        #expect(next?.kind == .milestone(.firstMonth))
    }

    @Test func aCountdownTodayShowsAsTodayAndMovesToThePastTheNextDay() throws {
        let trip = countdown("Trip", "2026-01-20")
        let dates = CoupleDates(countdowns: [trip])

        let onTheDay = timeline().upcoming(startedOn: nil, dates: dates, now: try day("2026-01-20"), milestoneLimit: 0)
        #expect(onTheDay.map(\.daysRemaining) == [0])

        let dayAfter = try day("2026-01-21")
        #expect(timeline().upcoming(startedOn: nil, dates: dates, now: dayAfter, milestoneLimit: 0).isEmpty)
        let past = timeline().past(startedOn: nil, dates: dates, now: dayAfter, limit: 4)
        #expect(past.map(\.kind) == [.countdown(trip)])
        #expect(past.first?.daysRemaining == -1)
    }

    @Test func birthdaysCountToTheNextOneAndNeverShowAsPast() throws {
        let dates = CoupleDates(birthdays: [me: "2000-03-14", partner: "1999-12-01"])
        let now = try day("2026-06-01")

        let upcoming = timeline().upcoming(startedOn: nil, dates: dates, now: now, milestoneLimit: 0)
        #expect(upcoming.map(\.kind) == [.birthday(userID: partner), .birthday(userID: me)])
        #expect(upcoming.map(\.date) == [try day("2026-12-01"), try day("2027-03-14")])
        #expect(timeline().past(startedOn: nil, dates: dates, now: now, limit: 4).isEmpty)
    }

    @Test func aBirthdayTodayCountsZero() throws {
        let next = timeline().nextBirthday(userID: me, birthday: "2000-06-01", today: try day("2026-06-01"))

        #expect(next?.daysRemaining == 0)
    }

    @Test func aLeapDayBirthdayFallsOnTheTwentyEighthInOtherYears() throws {
        let inCommonYear = timeline().nextBirthday(userID: me, birthday: "2000-02-29", today: try day("2026-01-01"))
        #expect(inCommonYear?.date == (try day("2026-02-28")))

        let inLeapYear = timeline().nextBirthday(userID: me, birthday: "2000-02-29", today: try day("2028-01-01"))
        #expect(inLeapYear?.date == (try day("2028-02-29")))
    }

    @Test func eventsOnTheSameDayHaveDistinctIDs() throws {
        let first = countdown("Dinner", "2026-02-08")
        let second = countdown("Concert", "2026-02-08")
        let upcoming = timeline().upcoming(
            startedOn: "2026-01-08",
            dates: CoupleDates(countdowns: [first, second], birthdays: [me: "2000-02-08"]),
            now: try day("2026-02-01"),
            milestoneLimit: 3
        )
        let sameDay = upcoming.filter { $0.daysRemaining == 7 }

        #expect(sameDay.count == 4)
        #expect(Set(sameDay.map(\.id)).count == 4)
        // The milestone leads the day, then the birthday, then the countdowns.
        #expect(sameDay.first?.kind == .milestone(.firstMonth))
        #expect(sameDay[1].kind == .birthday(userID: me))
    }

    @Test func queuedWritesLayOverTheServerCopyInOrder() {
        let trip = countdown("Trip", "2026-01-20")
        let server = CoupleDates(countdowns: [trip], birthdays: [me: "2000-03-14"])
        var renamed = trip
        renamed.title = "Bergen"
        let added = countdown("Concert", "2026-02-01")

        let local = server.applying([
            .save(renamed),
            .save(added),
            .delete(added.id),
            .birthday(SetBirthdayPayload(userID: me, birthday: nil)),
            .birthday(SetBirthdayPayload(userID: partner, birthday: "1999-12-01")),
        ])

        #expect(local.countdowns == [renamed])
        #expect(local.birthdays == [partner: "1999-12-01"])
    }
}
