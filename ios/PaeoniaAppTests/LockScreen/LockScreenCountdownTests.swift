import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenCountdownTests {
    typealias Support = LockScreenTestSupport

    private func countdown(
        _ title: String,
        _ target: LockScreenCalendarDate,
        createdAt: Date
    ) -> LockScreenSnapshot.Countdown {
        .init(id: title, title: title, targetDate: target, createdAt: createdAt)
    }

    @Test func picksTodayTomorrowAndLaterDays() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 17, 9, in: calendar)
        let created = Support.date(2_026, 9, 1, in: calendar)

        func remaining(_ target: LockScreenCalendarDate) -> LockScreenCountdown.Remaining? {
            let list = [countdown("A", target, createdAt: created)]
            return LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.remaining
        }

        #expect(remaining(Support.day(2_026, 10, 17)) == .today)
        #expect(remaining(Support.day(2_026, 10, 18)) == .tomorrow)
        #expect(remaining(Support.day(2_026, 10, 29)) == .days(12))
    }

    @Test func dropsPastCountdownsAndKeepsServerOrder() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 17, 9, in: calendar)
        let created = Support.date(2_026, 9, 1, in: calendar)
        let list = [
            countdown("Yesterday", Support.day(2_026, 10, 16), createdAt: created),
            countdown("Soon", Support.day(2_026, 10, 20), createdAt: created),
            countdown("Later", Support.day(2_026, 11, 20), createdAt: created),
        ]

        #expect(LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.title == "Soon")
        #expect(LockScreenCountdown.next(in: [list[0]], now: now, calendar: calendar) == nil)
        #expect(LockScreenCountdown.next(in: [], now: now, calendar: calendar) == nil)
    }

    @Test func dayMathUsesTheDeviceClockAcrossDaylightSavingTime() {
        let calendar = Support.calendar("Europe/Oslo")
        let now = Support.date(2_026, 10, 24, 23, 30, in: calendar)
        let created = Support.date(2_026, 9, 1, in: calendar)
        // The clocks go back on 25 October, so the 26th is 49 hours after this moment.
        let result = LockScreenCountdown.next(
            in: [countdown("A", Support.day(2_026, 10, 26), createdAt: created)],
            now: now,
            calendar: calendar
        )
        #expect(result?.remaining == .days(2))
    }

    @Test func progressGoesFromCreationToTheStartOfTheTargetDay() {
        let calendar = Support.calendar("UTC")
        let created = Support.date(2_026, 10, 1, 0, 0, in: calendar)
        let list = [countdown("A", Support.day(2_026, 10, 21), createdAt: created)]

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
        let list = [countdown("A", Support.day(2_026, 10, 17), createdAt: now.addingTimeInterval(-60))]
        #expect(LockScreenCountdown.next(in: list, now: now, calendar: calendar)?.progress == 1)
    }
}
