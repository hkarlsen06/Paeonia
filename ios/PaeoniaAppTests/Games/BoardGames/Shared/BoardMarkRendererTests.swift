import CoreGraphics
import Testing
@testable import PaeoniaApp

/// The square a mark is cropped to before the boards show it.
struct BoardMarkRendererTests {
    @Test func cropIsASquareCenteredOnTheStrokesWithPadding() {
        let bounds = CGRect(x: 20, y: 100, width: 200, height: 140)
        let crop = BoardMarkRenderer.cropRect(around: bounds)

        #expect(crop.width == crop.height)
        #expect(crop.midX == bounds.midX)
        #expect(crop.midY == bounds.midY)
        #expect(crop.insetBy(dx: crop.width * 0.05, dy: crop.width * 0.05).contains(bounds))
    }

    @Test func aTinyMarkIsEnlargedAtMostTwice() {
        let crop = BoardMarkRenderer.cropRect(around: CGRect(x: 10, y: 10, width: 8, height: 8))

        #expect(crop.width == BoardMarkRenderer.canvasSide / 2)
        #expect(crop.midX == 14)
        #expect(crop.midY == 14)
    }
}
