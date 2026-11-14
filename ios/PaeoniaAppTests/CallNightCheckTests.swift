import Foundation
import Testing
@testable import PaeoniaApp

struct CallNightCheckTests {
    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    /// `hour`:`minute` UTC on `month`/`day` 2026.
    private func utc(month: Int = 11, day: Int = 14, _ hour: Int, _ minute: Int = 0) throws -> Date {
        var components = DateComponents(year: 2_026, month: month, day: day, hour: hour, minute: minute)
        components.timeZone = try zone("UTC")
        return try #require(Calendar(identifier: .gregorian).date(from: components))
    }

    @Test func nightStartsAtTenOnThePartnersClock() throws {
        // Oslo is UTC+1 in November.
        let oslo = try zone("Europe/Oslo")
        #expect(!CallNightCheck.isNight(at: try utc(20, 59), in: oslo))
        #expect(CallNightCheck.isNight(at: try utc(21, 0), in: oslo))
    }

    @Test func nightEndsAtSevenOnThePartnersClock() throws {
        let oslo = try zone("Europe/Oslo")
        #expect(CallNightCheck.isNight(at: try utc(5, 59), in: oslo))
        #expect(!CallNightCheck.isNight(at: try utc(6, 0), in: oslo))
    }

    @Test func usesThePartnersTimeZoneAndNotTheCallers() throws {
        // 14:00 in Oslo is 22:00 in Tokyo.
        let afternoonInOslo = try utc(13)
        #expect(!CallNightCheck.isNight(at: afternoonInOslo, in: try zone("Europe/Oslo")))
        #expect(CallNightCheck.isNight(at: afternoonInOslo, in: try zone("Asia/Tokyo")))
    }

    @Test func followsDaylightSavingTime() throws {
        // 05:30 UTC on 29 March 2026 is 07:30 in Oslo once the clocks have gone forward.
        let oslo = try zone("Europe/Oslo")
        #expect(!CallNightCheck.isNight(at: try utc(month: 3, day: 29, 5, 30), in: oslo))
        // The day before, the same moment is 06:30, still night.
        #expect(CallNightCheck.isNight(at: try utc(month: 3, day: 28, 5, 30), in: oslo))
    }
}
