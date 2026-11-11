import Foundation
import Testing
@testable import PaeoniaApp

/// The Us tab visit card names the same last day together as the server, which runs visits that
/// overlap or follow on the next day into one stretch (`backend/convex/lib/together.ts`).
struct HomeVisitCardStateTests {
    private static let today = LockScreenCalendarDate(year: 2_026, month: 11, day: 10)
    private static let bergen = MemoryPlace(
        name: "Bryggen", latitude: 60.397, longitude: 5.324, city: "Bergen", countryCode: "NO"
    )
    private static let oslo = MemoryPlace(
        name: "Aker Brygge", latitude: 59.91, longitude: 10.73, city: "Oslo", countryCode: "NO"
    )

    private static func visit(_ start: String, _ end: String, _ place: MemoryPlace? = nil) -> Visit {
        Visit(id: UUID(), startDate: start, endDate: end, place: place)
    }

    private static func card(_ visits: [Visit], restsTogether: Bool = false) -> HomeVisitCardState {
        HomeVisitCardState(
            visits: CoupleVisits(visits: visits),
            on: today,
            restsTogether: restsTogether,
            promptReturnDay: nil
        )
    }

    @Test func backToBackAndOverlappingVisitsEndOnTheLastDayOfTheStretch() {
        let state = Self.card([
            Self.visit("2026-11-08", "2026-11-11", Self.bergen),
            Self.visit("2026-11-10", "2026-11-12", Self.oslo),
            Self.visit("2026-11-13", "2026-11-15"),
        ])
        #expect(state == .together(until: LockScreenCalendarDate(year: 2_026, month: 11, day: 15), place: Self.oslo))
    }

    @Test func aDayApartEndsTheStretch() {
        let state = Self.card([
            Self.visit("2026-11-09", "2026-11-11", Self.bergen),
            Self.visit("2026-11-13", "2026-11-15", Self.oslo),
        ])
        #expect(state == .together(until: LockScreenCalendarDate(year: 2_026, month: 11, day: 11), place: Self.bergen))
    }

    @Test func aDayTogetherByLocationAloneHasNoLastDay() {
        let upcoming = Self.visit("2026-11-20", "2026-11-22")
        #expect(Self.card([upcoming], restsTogether: true) == .together(until: nil, place: nil))
        #expect(Self.card([upcoming]) == .visit(upcoming))
    }
}
