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
}
