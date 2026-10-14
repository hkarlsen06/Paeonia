import CoreGraphics
import Testing
@testable import PaeoniaApp

/// How big the square is. A square with a strip above it is taller than wide, and
/// the plain square must come out exactly as before.
struct GameMetricsTests {
    private let size = CGSize(width: 600, height: 800)

    @Test func theDefaultRatioIsOneForAPlainSquare() {
        let measured = (side: CGFloat(200), content: CGFloat(400), bottom: CGFloat(100))

        #expect(
            GameMetrics.fittedSide(
                in: size,
                measuredSide: measured.side,
                contentHeight: measured.content,
                bottomHeight: measured.bottom
            ) == GameMetrics.fittedSide(
                in: size,
                measuredSide: measured.side,
                contentHeight: measured.content,
                bottomHeight: measured.bottom,
                heightRatio: 1
            )
        )
        #expect(GameMetrics.squareSide(in: size) == GameMetrics.squareSide(in: size, heightRatio: 1))
    }

    @Test func aPlainSquareGrowsByTheWholeSlack() {
        // 800 - 100 - 400 - scroll padding is the slack, and the square takes all of it.
        let slack = size.height - 100 - 400 - GameMetrics.scrollPadding

        let side = GameMetrics.fittedSide(in: size, measuredSide: 200, contentHeight: 400, bottomHeight: 100)

        #expect(side == (200 + slack).rounded(.down))
    }

    @Test func aSquareWithAStripGrowsByTheSlackDividedByTheRatio() {
        let ratio: CGFloat = 1.12
        let slack = size.height - 100 - 400 - GameMetrics.scrollPadding

        let side = GameMetrics.fittedSide(
            in: size,
            measuredSide: 200,
            contentHeight: 400,
            bottomHeight: 100,
            heightRatio: ratio
        )

        #expect(side == (200 + slack / ratio).rounded(.down))
        // The strip and the canvas together fill the height without passing it.
        let used = 100 + (400 + (side - 200) * ratio) + GameMetrics.scrollPadding
        #expect(used <= size.height)
        #expect(size.height - used < ratio)
    }

    @Test func aTallerSquareGetsASmallerSideBeforeTheRowsAreMeasured() {
        let shortPhone = CGSize(width: 390, height: 600)
        let wide = CGSize(width: 1_000, height: 500)

        #expect(GameMetrics.squareSide(in: shortPhone, heightRatio: 1.12) < GameMetrics.squareSide(in: shortPhone))
        #expect(GameMetrics.squareSide(in: wide, heightRatio: 1.12) < GameMetrics.squareSide(in: wide))
    }
}
