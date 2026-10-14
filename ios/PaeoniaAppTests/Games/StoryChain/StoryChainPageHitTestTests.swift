import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

/// Which line a tap lands on, worked out from the rectangles the renderer records.
struct StoryChainPageHitTestTests {
    private let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID()
    private let second = UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID()

    /// Two rows of text 6 points apart: the first line fills row one, and the
    /// second line fills the left half of row two.
    private var frames: [UUID: [CGRect]] {
        [
            first: [CGRect(x: 0, y: 0, width: 100, height: 20)],
            second: [CGRect(x: 0, y: 26, width: 60, height: 20)],
        ]
    }

    @Test func aTapInsideARectangleHitsItsLine() {
        let hit = StoryChainLineHitTest.hit(at: CGPoint(x: 40, y: 10), in: frames)

        #expect(hit?.lineID == first)
        #expect(hit?.rect == CGRect(x: 0, y: 0, width: 100, height: 20))
    }

    @Test func aTapBesideTheTextHitsNothing() {
        // Row two ends at x = 60.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 80, y: 36), in: frames) == nil)
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: -1, y: 10), in: frames) == nil)
    }

    @Test func aTapInTheGapBetweenRowsHitsTheNearerRow() {
        // The gap runs from y = 20 to y = 26.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 21), in: frames)?.lineID == first)
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 25), in: frames)?.lineID == second)
    }

    @Test func aTapInTheMiddleOfTheGapGoesToTheHigherRow() {
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 23), in: frames)?.lineID == first)
    }

    @Test func aTapFurtherThanTheSlopFromARowHitsNothing() {
        // 4 points below row two, which ends at y = 46.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 50), in: frames) == nil)
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 49), in: frames)?.lineID == second)
        // Without slop the gap hits nothing.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 22), in: frames, verticalSlop: 0) == nil)
    }

    @Test func aRectangleThatHoldsTheTapBeatsOneWithinTheSlop() {
        let overlapping: [UUID: [CGRect]] = [
            first: [CGRect(x: 0, y: 0, width: 100, height: 22)],
            second: [CGRect(x: 0, y: 20, width: 100, height: 20)],
        ]

        // y = 21 is inside both rectangles, so the higher row wins the tie.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 5, y: 21), in: overlapping)?.lineID == first)
        // y = 30 is only inside the second.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 5, y: 30), in: overlapping)?.lineID == second)
    }

    @Test func aLineThatWrapsHasOneRectanglePerRow() {
        let wrapped: [UUID: [CGRect]] = [
            first: [
                CGRect(x: 40, y: 0, width: 60, height: 20),
                CGRect(x: 0, y: 26, width: 30, height: 20),
            ],
        ]

        let hit = StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 30), in: wrapped)

        #expect(hit?.lineID == first)
        #expect(hit?.rect == CGRect(x: 0, y: 26, width: 30, height: 20))
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 10, y: 10), in: wrapped) == nil)
    }

    @Test func twoLinesOnOneRowMeetAtTheirSharedEdge() {
        let sameRow: [UUID: [CGRect]] = [
            first: [CGRect(x: 0, y: 0, width: 50, height: 20)],
            second: [CGRect(x: 50, y: 0, width: 50, height: 20)],
        ]

        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 49, y: 10), in: sameRow)?.lineID == first)
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 51, y: 10), in: sameRow)?.lineID == second)
        // The shared edge belongs to the left line, the same every time.
        #expect(StoryChainLineHitTest.hit(at: CGPoint(x: 50, y: 10), in: sameRow)?.lineID == first)
    }

    @Test func noRectanglesMeansNoHit() {
        #expect(StoryChainLineHitTest.hit(at: .zero, in: [:]) == nil)
    }

    @Test func theFrameBoxHandsTheRecordedRectanglesToTheTapTest() {
        let box = StoryChainLineFrames()
        #expect(box.hit(at: CGPoint(x: 10, y: 10)) == nil)

        box.replace(with: frames)
        #expect(box.hit(at: CGPoint(x: 10, y: 10))?.lineID == first)

        box.replace(with: [:])
        #expect(box.hit(at: CGPoint(x: 10, y: 10)) == nil)
    }
}
