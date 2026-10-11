import CoreLocation
import Foundation
import Testing
@testable import PaeoniaApp

struct CoupleMapFramingTests {
    @Test
    func separatedLeavesPinsThatAreAlreadyApartUntouched() {
        let first = CGPoint(x: 100, y: 100)
        let second = CGPoint(x: 200, y: 100)

        let (firstPin, secondPin) = CoupleMapFraming.separated(first, second, minimumDistance: 42)

        #expect(firstPin == first)
        #expect(secondPin == second)
    }

    @Test
    func separatedSpreadsOverlappingPinsAroundTheirMidpoint() {
        let (firstPin, secondPin) = CoupleMapFraming.separated(
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 104),
            minimumDistance: 42
        )

        #expect(abs(hypot(secondPin.x - firstPin.x, secondPin.y - firstPin.y) - 42) < 0.001)
        #expect(firstPin.x == 100 && secondPin.x == 100)
        #expect(abs((firstPin.y + secondPin.y) / 2 - 102) < 0.001)
        #expect(firstPin.y < secondPin.y)
    }

    @Test
    func separatedSpreadsPinsOnTheSameSpotSideways() {
        let spot = CGPoint(x: 150, y: 80)

        let (firstPin, secondPin) = CoupleMapFraming.separated(spot, spot, minimumDistance: 42)

        #expect(firstPin == CGPoint(x: 129, y: 80))
        #expect(secondPin == CGPoint(x: 171, y: 80))
    }

    // About 9 m and 1.1 km north of `oslo`.
    private let oslo = CLLocationCoordinate2D(latitude: 59.9139, longitude: 10.7522)
    private let nineMetersAway = CLLocationCoordinate2D(latitude: 59.91398, longitude: 10.7522)
    private let farAway = CLLocationCoordinate2D(latitude: 59.9239, longitude: 10.7522)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func areTogetherWhenCloseWithRecentFixes() {
        #expect(CoupleMapFraming.areTogether(
            current: oslo,
            currentCapturedAt: now,
            partner: nineMetersAway,
            partnerCapturedAt: now.addingTimeInterval(-22 * 60),
            partnerIsStale: false
        ))
    }

    @Test
    func areNotTogetherWhenFarApart() {
        #expect(!CoupleMapFraming.areTogether(
            current: oslo,
            currentCapturedAt: now,
            partner: farAway,
            partnerCapturedAt: now,
            partnerIsStale: false
        ))
    }

    @Test
    func areNotTogetherWhenFixesAreHoursApart() {
        #expect(!CoupleMapFraming.areTogether(
            current: oslo,
            currentCapturedAt: now,
            partner: nineMetersAway,
            partnerCapturedAt: now.addingTimeInterval(-2 * 60 * 60),
            partnerIsStale: false
        ))
    }

    @Test
    func areNotTogetherWhenPartnerLocationIsStale() {
        #expect(!CoupleMapFraming.areTogether(
            current: oslo,
            currentCapturedAt: now,
            partner: nineMetersAway,
            partnerCapturedAt: now,
            partnerIsStale: true
        ))
    }
}
