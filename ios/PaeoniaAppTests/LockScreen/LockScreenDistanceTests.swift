import Foundation
import Testing
@testable import PaeoniaApp

struct LockScreenDistanceTests {
    private func distance(_ meters: Double?) -> LockScreenDistance {
        LockScreenDistance(meters.map { .init(meters: $0, asOf: .distantPast) })
    }

    @Test func underAKilometerIsTogether() {
        #expect(distance(0) == .together)
        #expect(distance(999.9) == .together)
        #expect(distance(1_000) == .apart(meters: 1_000))
        #expect(distance(7_750_000) == .apart(meters: 7_750_000))
    }

    @Test func missingOrBrokenDistanceIsUnavailable() {
        #expect(distance(nil) == .unavailable)
        #expect(distance(-5) == .unavailable)
        #expect(distance(.nan) == .unavailable)
        #expect(distance(.infinity) == .unavailable)
    }

    @Test func norwegianLocaleGetsKilometers() {
        let text = LockScreenDistance.text(meters: 7_750_000, locale: Locale(identifier: "nb_NO"))
        #expect(text.number.filter(\.isNumber) == "7750")
        #expect(text.unit == "km")
        #expect(text.combined.contains("km"))
        #expect(text.combined.hasSuffix(" km"))
    }

    @Test func usAndUkLocalesGetMiles() {
        let us = LockScreenDistance.text(meters: 7_750_000, locale: Locale(identifier: "en_US"))
        #expect(us.number == "4,816")
        #expect(us.unit == "mi")
        #expect(us.combined.contains("4,816"))

        let uk = LockScreenDistance.text(meters: 7_750_000, locale: Locale(identifier: "en_GB"))
        #expect(uk.unit == "mi")
    }

    @Test func shortDistancesKeepOneDecimal() {
        let text = LockScreenDistance.text(meters: 2_500, locale: Locale(identifier: "en_CA"))
        #expect(text.number == "2.5")
        #expect(text.unit == "km")
    }
}
