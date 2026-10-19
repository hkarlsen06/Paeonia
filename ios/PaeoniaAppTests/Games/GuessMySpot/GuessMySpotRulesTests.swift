import Foundation
import Testing
@testable import PaeoniaApp

/// The scoring, the distance and the place and day text rules. The server has the
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

    @Test func theDayReadsAsADateWithoutATimeZoneShift() {
        let text = GuessMySpotText.takenOn("2024-06-12", locale: Locale(identifier: "en_US"))
        #expect(text == "June 12, 2024")
        #expect(GuessMySpotText.takenOn("12 June", locale: Locale(identifier: "en_US")) == nil)
        #expect(GuessMySpotDay.string(year: 2_024, month: 2, day: 30) == nil)
        #expect(GuessMySpotDay.string(year: 2_024, month: 2, day: 29) == "2024-02-29")
    }
}
