import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the contextual milestone schedule shown on the Us-tab countdown card. The
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

        #expect(milestone?.kind == .days(1000))
        #expect(milestone?.daysRemaining == 3)
    }

    @Test func unparseableStartDateHasNoMilestone() throws {
        #expect(calculator().nextMilestone(startedOn: "not-a-date", now: try day("2026-06-01")) == nil)
    }
}
