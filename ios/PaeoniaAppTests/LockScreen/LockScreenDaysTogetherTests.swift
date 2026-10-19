import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenDaysTogetherTests {
    typealias Support = LockScreenTestSupport

    @Test func countsZeroOnTheStartDay() {
        let calendar = Support.calendar("Europe/Oslo")
        let model = LockScreenDaysTogether(
            startedOn: Support.day(2_026, 10, 17),
            now: Support.date(2_026, 10, 17, 23, 59, in: calendar),
            calendar: calendar
        )
        #expect(model?.days == 0)
    }

    @Test func countsCalendarDaysAcrossTheSpringDaylightSavingChange() {
        // Oslo skips an hour on 29 March 2026. A 24-hour division would be off by one.
        let calendar = Support.calendar("Europe/Oslo")
        let model = LockScreenDaysTogether(
            startedOn: Support.day(2_026, 3, 28),
            now: Support.date(2_026, 3, 30, 0, 30, in: calendar),
            calendar: calendar
        )
        #expect(model?.days == 2)
    }

    @Test func countsCalendarDaysAcrossTheAutumnDaylightSavingChange() {
        let calendar = Support.calendar("Europe/Oslo")
        let model = LockScreenDaysTogether(
            startedOn: Support.day(2_026, 10, 24),
            now: Support.date(2_026, 10, 26, 23, 30, in: calendar),
            calendar: calendar
        )
        #expect(model?.days == 2)
    }

    @Test func countsLeapDays() {
        let calendar = Support.calendar("UTC")
        func days(from start: LockScreenCalendarDate, to end: Date) -> Int? {
            LockScreenDaysTogether(startedOn: start, now: end, calendar: calendar)?.days
        }

        #expect(days(from: Support.day(2_024, 2, 28), to: Support.date(2_024, 3, 1, in: calendar)) == 2)
        #expect(days(from: Support.day(2_023, 2, 28), to: Support.date(2_023, 3, 1, in: calendar)) == 1)
        #expect(days(from: Support.day(2_024, 1, 1), to: Support.date(2_025, 1, 1, in: calendar)) == 366)
    }

    @Test func usesTheDeviceCalendarForToday() {
        // 23:30 UTC on the 16th is already the 17th in Tokyo.
        let utc = Support.calendar("UTC")
        let tokyo = Support.calendar("Asia/Tokyo")
        let now = Support.date(2_026, 10, 16, 23, 30, in: utc)
        #expect(LockScreenDaysTogether(startedOn: Support.day(2_026, 10, 16), now: now, calendar: utc)?.days == 0)
        #expect(LockScreenDaysTogether(startedOn: Support.day(2_026, 10, 16), now: now, calendar: tokyo)?.days == 1)
    }

    @Test func countsGregorianDaysOnAPhoneSetToTheBuddhistCalendar() {
        // The Buddhist calendar calls 2026 year 2569. The server's dates are Gregorian.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .gmt
        let now = Support.date(2_026, 10, 17, in: Support.calendar("Europe/Oslo"))
        #expect(LockScreenDaysTogether(startedOn: Support.day(2_026, 10, 7), now: now, calendar: buddhist)?.days == 10)
        let midnight = Support.date(2_026, 10, 17, 0, in: Support.calendar("Europe/Oslo"))
        #expect(Support.day(2_026, 10, 17).startOfDay(in: buddhist) == midnight)
    }

    @Test func hasNoCountWithoutAStartDateAndNeverGoesNegative() {
        let calendar = Support.calendar("UTC")
        let now = Support.date(2_026, 10, 17, in: calendar)
        #expect(LockScreenDaysTogether(startedOn: nil, now: now, calendar: calendar) == nil)
        #expect(LockScreenDaysTogether(startedOn: Support.day(2_026, 10, 20), now: now, calendar: calendar)?.days == 0)
    }
}
