import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenCountdownTests {
    typealias Support = LockScreenTestSupport

    private func countdown(
        _ title: String,
        _ target: LockScreenCalendarDate,
        createdAt: Date,
        yearly: Bool = false
    ) -> LockScreenSnapshot.DatedCountdown {
        .init(id: title, title: title, targetDate: target, repeatsYearly: yearly, createdAt: createdAt)
    }

    private func dates(
        _ countdowns: [LockScreenSnapshot.DatedCountdown],
        birthdays: [LockScreenSnapshot.Birthday] = []
    ) -> LockScreenSnapshot.Dates {
        .init(countdowns: countdowns, birthdays: birthdays)
    }

    @Test func picksTodayTomorrowAndLaterDays() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 17, 9, in: calendar)
        let created = Support.date(2_026, 9, 1, in: calendar)

        func remaining(_ target: LockScreenCalendarDate) -> LockScreenCountdown.Remaining? {
            let list = dates([countdown("A", target, createdAt: created)])
            return LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.remaining
        }

        #expect(remaining(Support.day(2_026, 10, 17)) == .today)
        #expect(remaining(Support.day(2_026, 10, 18)) == .tomorrow)
        #expect(remaining(Support.day(2_026, 10, 29)) == .days(12))
    }

    @Test func dropsPastCountdownsAndPicksTheSoonest() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 17, 9, in: calendar)
        let created = Support.date(2_026, 9, 1, in: calendar)
        let list = [
            countdown("Yesterday", Support.day(2_026, 10, 16), createdAt: created),
            countdown("Later", Support.day(2_026, 11, 20), createdAt: created),
            countdown("Soon", Support.day(2_026, 10, 20), createdAt: created),
        ]

        #expect(LockScreenCountdown.next(in: dates(list), now: now, calendar: calendar)?.title == "Soon")
        #expect(LockScreenCountdown.next(in: dates([list[0]]), now: now, calendar: calendar) == nil)
        #expect(LockScreenCountdown.next(in: dates([]), now: now, calendar: calendar) == nil)
    }

    @Test func aBirthdayIsNotACountdown() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 17, 9, in: calendar)
        let birthday = LockScreenSnapshot.Birthday(isMine: true, birthday: Support.day(2_000, 10, 18))
        let later = countdown("Later", Support.day(2_026, 12, 1), createdAt: now)

        let both = dates([later], birthdays: [birthday])
        #expect(LockScreenCountdown.next(in: both, now: now, calendar: calendar)?.title == "Later")
        #expect(LockScreenCountdown.next(in: dates([], birthdays: [birthday]), now: now, calendar: calendar) == nil)
    }

    @Test func dayMathUsesTheDeviceClockAcrossDaylightSavingTime() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 24, 23, 30, in: calendar)
        let created = Support.date(2_026, 9, 1, in: calendar)
        // The clocks go back on 25 October, so the 26th is 49 hours after this moment.
        let result = LockScreenCountdown.next(
            in: dates([countdown("A", Support.day(2_026, 10, 26), createdAt: created)]),
            now: now,
            calendar: calendar
        )
        #expect(result?.remaining == .days(2))
    }

    @Test func progressGoesFromCreationToTheStartOfTheTargetDay() {
        let calendar = Support.calendar("UTC")
        let created = Support.date(2_026, 10, 1, 0, 0, in: calendar)
        let list = dates([countdown("A", Support.day(2_026, 10, 21), createdAt: created)])

        func progress(_ now: Date) -> Double? {
            LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.progress
        }

        #expect(progress(created) == 0)
        #expect(progress(Support.date(2_026, 10, 11, 0, 0, in: calendar)) == 0.5)
        #expect(progress(Support.date(2_026, 10, 21, 8, 0, in: calendar)) == 1)
    }

    @Test func progressIsFullWhenMadeOnTheTargetDay() {
        let calendar = Support.calendar("UTC")
        let now = Support.date(2_026, 10, 17, 9, in: calendar)
        let list = dates([countdown("A", Support.day(2_026, 10, 17), createdAt: now.addingTimeInterval(-60))])
        #expect(LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.progress == 1)
    }

    /// A snapshot fetched on the day itself is reused for up to a week, so the widget has to
    /// find next year's day on its own after midnight.
    @Test func aYearlyCountdownMovesToNextYearAfterItsDay() {
        let calendar = Support.calendar("Europe/Oslo")
        let created = Support.date(2_023, 10, 1, in: calendar)
        let list = dates([countdown("Met", Support.day(2_023, 10, 21), createdAt: created, yearly: true)])

        let onTheDay = LockScreenCountdown.next(
            in: list, now: Support.date(2_026, 10, 21, 9, in: calendar), calendar: calendar
        )
        #expect(onTheDay?.remaining == .today)

        let nextMorning = LockScreenCountdown.next(
            in: list, now: Support.date(2_026, 10, 22, 0, 5, in: calendar), calendar: calendar
        )
        #expect(nextMorning?.title == "Met")
        #expect(nextMorning?.remaining == .days(364))
    }

    @Test func aYearlyCountdownsBarRestartsEachYear() {
        let calendar = Support.calendar("UTC")
        let created = Support.date(2_023, 10, 1, 0, 0, in: calendar)
        let list = dates([countdown("Met", Support.day(2_023, 10, 21), createdAt: created, yearly: true)])

        func progress(_ now: Date) -> Double? {
            LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.progress
        }

        // First year: from the day it was made (20 days) to the day itself.
        #expect(progress(Support.date(2_023, 10, 11, 0, 0, in: calendar)) == 0.5)
        // Later years run from the 21 October before (365 days), so the bar is full on the day.
        #expect(progress(Support.date(2_025, 10, 21, 0, 0, in: calendar)) == 1)
        let halfway = Support.date(2_026, 4, 21, 12, 0, in: calendar)
        #expect(abs((progress(halfway) ?? 0) - 182.5 / 365) < 0.001)
        // The day after, the bar starts over towards next year.
        #expect(progress(Support.date(2_026, 10, 22, 0, 0, in: calendar)) == 1.0 / 365)
    }

    @Test func aYearlyCountdownAheadOfItsFirstDayRunsFromWhenItWasMade() {
        let calendar = Support.calendar("UTC")
        let created = Support.date(2_026, 10, 1, 0, 0, in: calendar)
        let list = dates([countdown("Trip", Support.day(2_026, 10, 21), createdAt: created, yearly: true)])
        let now = Support.date(2_026, 10, 11, 0, 0, in: calendar)
        #expect(LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.progress == 0.5)
    }
}
