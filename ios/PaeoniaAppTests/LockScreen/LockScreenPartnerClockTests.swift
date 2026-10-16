import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenPartnerClockTests {
    typealias Support = LockScreenTestSupport

    private let utc = Support.calendar("UTC")

    private func clock(_ id: String) throws -> LockScreenPartnerClock {
        try #require(LockScreenPartnerClock(timeZoneID: id))
    }

    @Test func rejectsMissingOrUnknownTimeZones() {
        #expect(LockScreenPartnerClock(timeZoneID: nil) == nil)
        #expect(LockScreenPartnerClock(timeZoneID: "") == nil)
        #expect(LockScreenPartnerClock(timeZoneID: "Mars/Olympus") == nil)
    }

    @Test func offsetCoversAheadBehindSameAndHalfHourZones() throws {
        let now = Support.date(2_026, 10, 17, 9, 15, in: utc) // Oslo is on summer time (+2)
        let oslo = try #require(TimeZone(identifier: "Europe/Oslo"))

        #expect(try clock("Asia/Kolkata").offset(at: now, from: oslo) == .ahead(minutes: 210))
        #expect(try clock("Asia/Tokyo").offset(at: now, from: oslo) == .ahead(minutes: 420))
        #expect(try clock("America/New_York").offset(at: now, from: oslo) == .behind(minutes: 360))
        #expect(try clock("Europe/Stockholm").offset(at: now, from: oslo) == .same)
        #expect(try clock("Asia/Kathmandu").offset(at: now, from: oslo) == .ahead(minutes: 225))
    }

    @Test func offsetFollowsDaylightSavingDifferencesBetweenRegions() throws {
        // Between 25 October and 1 November, Oslo is back on winter time (+1)
        // while New York is still on summer time (-4).
        let now = Support.date(2_026, 10, 28, 12, in: utc)
        let oslo = try #require(TimeZone(identifier: "Europe/Oslo"))
        #expect(try clock("America/New_York").offset(at: now, from: oslo) == .behind(minutes: 300))
    }

    @Test func handAnglesFollowTheClock() throws {
        let kolkata = try clock("Asia/Kolkata")
        let now = Support.date(2_026, 10, 17, 9, 15, in: utc) // 14:45 in Kolkata

        #expect(kolkata.hourAndMinute(at: now) == (14, 45))
        #expect(kolkata.hourHandDegrees(at: now) == 82.5)
        #expect(kolkata.minuteHandDegrees(at: now) == 270)

        let midnight = try clock("UTC")
        let start = Support.date(2_026, 10, 17, 0, 0, in: utc)
        #expect(midnight.hourHandDegrees(at: start) == 0)
        #expect(midnight.minuteHandDegrees(at: start) == 0)
        #expect(midnight.hourHandDegrees(at: Support.date(2_026, 10, 17, 12, 0, in: utc)) == 0)
        #expect(midnight.hourHandDegrees(at: Support.date(2_026, 10, 17, 3, 30, in: utc)) == 105)
    }

    @Test func daytimeRunsFromSixToTwentyInThePartnersZone() throws {
        let utcClock = try clock("UTC")
        func isDay(_ hour: Int, _ minute: Int) -> Bool {
            utcClock.isDaytime(at: Support.date(2_026, 10, 17, hour, minute, in: utc))
        }

        #expect(!isDay(5, 59))
        #expect(isDay(6, 0))
        #expect(isDay(19, 59))
        #expect(!isDay(20, 0))
        #expect(!isDay(0, 0))

        // 22:00 UTC is 07:00 in Tokyo, which is day there.
        #expect(try clock("Asia/Tokyo").isDaytime(at: Support.date(2_026, 10, 17, 22, 0, in: utc)))
    }

    @Test func timeTextUsesThePartnersZone() throws {
        let now = Support.date(2_026, 10, 17, 9, 15, in: utc)
        let text = try clock("Asia/Kolkata").timeText(at: now, locale: Locale(identifier: "en_GB"))
        #expect(text == "14:45")
    }

    @Test func timeTextUsesTwoDigitHoursIn24HourLocales() throws {
        let now = Support.date(2_026, 10, 17, 23, 5, in: utc)
        #expect(try clock("Europe/Oslo").timeText(at: now, locale: Locale(identifier: "nb_NO")) == "01:05")
        let us = try clock("Europe/Oslo").timeText(at: now, locale: Locale(identifier: "en_US"))
        #expect(us.hasPrefix("1:05") && us.hasSuffix("AM"))
    }

    @Test func timelineHasOneEntryPerMinuteStartingAtTheCurrentMinute() throws {
        let now = Support.date(2_026, 10, 17, 12, 0, in: utc).addingTimeInterval(45)
        let dates = LockScreenPartnerClock.minuteEntryDates(from: now)

        #expect(dates.count == 360)
        #expect(dates.first == Support.date(2_026, 10, 17, 12, 0, in: utc))
        #expect(dates.last == Support.date(2_026, 10, 17, 17, 59, in: utc))
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 60 })
    }
}
