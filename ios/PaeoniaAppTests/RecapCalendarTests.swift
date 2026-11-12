import Testing
@testable import PaeoniaApp

struct RecapCalendarTests {
    @Test func latestAnniversaryIsTheNewestOneAtLeastAYearAfterTheStart() {
        #expect(RecapCalendar.latestAnniversary(startedOn: "2025-11-11", today: "2026-11-11") == "2026-11-11")
        #expect(RecapCalendar.latestAnniversary(startedOn: "2025-11-11", today: "2026-11-10") == nil)
        #expect(RecapCalendar.latestAnniversary(startedOn: "2021-03-05", today: "2026-03-04") == "2025-03-05")
    }

    @Test func aTwentyNinthOfFebruaryStartFallsOnTheTwentyEighthInOtherYears() {
        #expect(RecapCalendar.latestAnniversary(startedOn: "2024-02-29", today: "2026-03-01") == "2026-02-28")
        #expect(RecapCalendar.latestAnniversary(startedOn: "2024-02-29", today: "2028-02-29") == "2028-02-29")
    }

    @Test func daysAreCountedAcrossTheYearEnd() {
        #expect(RecapCalendar.days(from: "2026-12-31", to: "2027-01-01") == 1)
        #expect(RecapCalendar.days(from: "2026-12-25", to: "2027-01-07") == 13)
        #expect(RecapCalendar.days(from: "2027-01-07", to: "2026-12-25") == -13)
    }
}
