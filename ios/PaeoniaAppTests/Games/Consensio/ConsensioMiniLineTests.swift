import CoreGraphics
import Testing
@testable import PaeoniaApp

/// The marks on a "What we know" row: apart when far, pushed apart until they
/// touch when close, and never off the line.
struct ConsensioMiniLineTests {
    @Test func farHeadsStayOnTheirPlaces() {
        let heads = ConsensioMiniLine.headCenters(spot: 40, guess: 200, head: 26, width: 300)
        #expect(heads.spot == 40)
        #expect(heads.guess == 200)
    }

    @Test func closeHeadsMoveApartUntilTheyTouch() {
        let heads = ConsensioMiniLine.headCenters(spot: 210, guess: 200, head: 26, width: 300)
        #expect(heads.guess == 192)
        #expect(heads.spot == 218)
    }

    @Test func headsAtAnEndStayOnTheLine() {
        let heads = ConsensioMiniLine.headCenters(spot: 13, guess: 13, head: 26, width: 300)
        #expect(heads.spot == 13)
        #expect(heads.guess == 39)
    }
}
