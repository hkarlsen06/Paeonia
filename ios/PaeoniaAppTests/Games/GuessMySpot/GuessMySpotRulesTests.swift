import Foundation
import Testing
@testable import PaeoniaApp

/// The scoring, the distance and the words the reveal uses. The server has the
/// same numbers in `backend/convex/lib/guessMySpot.ts`.
struct GuessMySpotRulesTests {
    @Test func pointsHalveEvery1500Kilometres() {
        #expect(GuessMySpotRules.points(distanceMeters: 0) == 5_000)
        #expect(GuessMySpotRules.points(distanceMeters: 200) == 5_000)
        #expect(GuessMySpotRules.points(distanceMeters: 10_000) == 4_977)
        #expect(GuessMySpotRules.points(distanceMeters: 100_000) == 4_774)
        #expect(GuessMySpotRules.points(distanceMeters: 500_000) == 3_969)
        #expect(GuessMySpotRules.points(distanceMeters: 1_500_000) == 2_500)
        #expect(GuessMySpotRules.points(distanceMeters: 5_000_000) == 496)
        #expect(GuessMySpotRules.points(distanceMeters: 20_000_000) == 0)
    }

    @Test func theVerdictFollowsTheDistance() {
        #expect(GuessMySpotRules.verdict(distanceMeters: 1_000) == .spotOn)
        #expect(GuessMySpotRules.verdict(distanceMeters: 1_001) == .soClose)
        #expect(GuessMySpotRules.verdict(distanceMeters: 25_000) == .soClose)
        #expect(GuessMySpotRules.verdict(distanceMeters: 25_001) == .close)
        #expect(GuessMySpotRules.verdict(distanceMeters: 300_000) == .close)
        #expect(GuessMySpotRules.verdict(distanceMeters: 300_001) == .far)
    }

    @Test func distanceIsTheGreatCircle() {
        let oslo = GuessMySpotCoordinate(latitude: 59.9139, longitude: 10.7522)
        let bergen = GuessMySpotCoordinate(latitude: 60.3913, longitude: 5.3221)
        let meters = GuessMySpotRules.distanceMeters(oslo, bergen)
        #expect((300_000...310_000).contains(meters))
        #expect(GuessMySpotRules.distanceMeters(oslo, oslo) == 0)
        // Across the 180th meridian the short way.
        let west = GuessMySpotCoordinate(latitude: 0, longitude: 179.5)
        let east = GuessMySpotCoordinate(latitude: 0, longitude: -179.5)
        #expect((110_000...112_000).contains(GuessMySpotRules.distanceMeters(west, east)))
    }

    @Test func theLineRunsAlongTheGreatCircle() {
        let oslo = GuessMySpotCoordinate(latitude: 59.9139, longitude: 10.7522)
        let bergen = GuessMySpotCoordinate(latitude: 60.3913, longitude: 5.3221)
        let start = GuessMySpotRules.intermediate(from: oslo, to: bergen, fraction: 0)
        let end = GuessMySpotRules.intermediate(from: oslo, to: bergen, fraction: 1)
        let middle = GuessMySpotRules.intermediate(from: oslo, to: bergen, fraction: 0.5)
        #expect(GuessMySpotRules.distanceMeters(start, oslo) < 1)
        #expect(GuessMySpotRules.distanceMeters(end, bergen) < 1)
        let half = GuessMySpotRules.distanceMeters(oslo, bergen) / 2
        #expect(abs(GuessMySpotRules.distanceMeters(oslo, middle) - half) < 5)
        // The same spot twice has no line to draw, and stays put.
        #expect(GuessMySpotRules.intermediate(from: oslo, to: oslo, fraction: 0.5) == oslo)
    }

    @Test func spotsOutsideTheMapAreRefused() {
        #expect(GuessMySpotRules.isValid(GuessMySpotCoordinate(latitude: 90, longitude: -180)))
        #expect(!GuessMySpotRules.isValid(GuessMySpotCoordinate(latitude: 90.5, longitude: 0)))
        #expect(!GuessMySpotRules.isValid(GuessMySpotCoordinate(latitude: 0, longitude: .nan)))
    }

    @Test func aPlaceNameIsTrimmedAndCapped() {
        #expect(GuessMySpotRules.placeName("  Bergen,\n  Norway ") == "Bergen, Norway")
        #expect(GuessMySpotRules.placeName("   ") == nil)
        #expect(GuessMySpotRules.placeName(nil) == nil)
        let long = String(repeating: "å", count: 200)
        #expect(GuessMySpotRules.placeName(long)?.unicodeScalars.count == 120)
    }

    @Test func distancesAreMetricInBothLanguages() {
        let english = Locale(identifier: "en_US")
        let norwegian = Locale(identifier: "nb_NO")
        #expect(GuessMySpotText.distance(354, locale: english) == "350 m")
        #expect(GuessMySpotText.distance(3_240, locale: english) == "3.2 km")
        #expect(GuessMySpotText.distance(3_240, locale: norwegian) == "3,2 km")
        #expect(GuessMySpotText.distance(1_234_000, locale: english) == "1,234 km")
        // The edges: no "10 m" for a guess right on it, no "1,000 m" and no "10.0 km".
        #expect(GuessMySpotText.distance(3, locale: english) == "3 m")
        #expect(GuessMySpotText.distance(997, locale: english) == "1.0 km")
        #expect(GuessMySpotText.distance(9_970, locale: english) == "10 km")
    }

    @Test func theDayReadsAsADateWithoutATimeZoneShift() {
        let text = GuessMySpotText.takenOn("2024-06-12", locale: Locale(identifier: "en_US"))
        #expect(text == "June 12, 2024")
        #expect(GuessMySpotText.takenOn("12 June", locale: Locale(identifier: "en_US")) == nil)
        #expect(GuessMySpotDay.string(year: 2_024, month: 2, day: 30) == nil)
        #expect(GuessMySpotDay.string(year: 2_024, month: 2, day: 29) == "2024-02-29")
    }

    @Test func aCounterEasesIntoItsFinalNumber() {
        #expect(GuessMySpotRevealScript.counted(4_977, step: 0, of: 10) == 0)
        #expect(GuessMySpotRevealScript.counted(4_977, step: 10, of: 10) == 4_977)
        let early = GuessMySpotRevealScript.counted(4_977, step: 3, of: 10)
        let late = GuessMySpotRevealScript.counted(4_977, step: 7, of: 10)
        #expect(early > 4_977 * 3 / 10 && late < 4_977)
    }

    @Test func theRevealPlaysItsBeatsInOrder() {
        let plan = GuessMySpotRevealPlan(verdict: .spotOn, distanceMeters: 400, points: 5_000)
        let steps = GuessMySpotRevealScript.steps(for: plan, schedule: .standard)
        let events = steps.map(\.event)
        let line = events.firstIndex(of: .line) ?? -1
        let drop = events.firstIndex(of: .drop) ?? -1
        let land = events.firstIndex(of: .land) ?? -1
        let verdict = events.firstIndex(of: .verdict(.spotOn)) ?? -1
        let card = events.firstIndex(of: .card) ?? -1
        #expect(events.first == .start)
        #expect(line < drop && drop < land && land < verdict && verdict < card)
        #expect(events.contains(.bloomEnd))
        #expect(events.last == .actions)
        #expect(steps.map(\.at) == steps.map(\.at).sorted())
    }
}
