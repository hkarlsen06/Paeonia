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
}
