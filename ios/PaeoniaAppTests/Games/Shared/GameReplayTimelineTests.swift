import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

struct GameReplayTimelineTests {
    private let halfSeconds: [TimeInterval] = [0, 0.5, 1, 1.5, 2]

    private func timeline(_ strokes: PKStroke...) -> GameReplayTimeline {
        GameReplayTimeline(drawing: PKDrawing(strokes: strokes))
    }

    @Test func emptyDrawingHasNoDuration() {
        let timeline = GameReplayTimeline(drawing: PKDrawing())

        #expect(timeline.duration == 0)
        #expect(timeline.drawing(at: 5).strokes.isEmpty)
    }

    @Test func strokesPlayInCreationOrderNotArrayOrder() {
        let late = ReplayFixtures.stroke(created: 10, offsets: [0, 1], y: 20)
        let early = ReplayFixtures.stroke(created: 0, offsets: [0, 1], y: 10)

        let items = timeline(late, early).items

        #expect(items.map { $0.stroke.path[0].location.y } == [10, 20])
        #expect(items[0].start == 0)
    }

    @Test func pauseBetweenStrokesIsCappedAtOneSecond() {
        let first = ReplayFixtures.stroke(created: 0, offsets: halfSeconds)
        let second = ReplayFixtures.stroke(created: 600, offsets: halfSeconds)

        let result = timeline(first, second)

        #expect(result.items[1].start == 3)
        #expect(result.duration == 5)
    }

    @Test func shortPauseKeepsItsLength() {
        let first = ReplayFixtures.stroke(created: 0, offsets: halfSeconds)
        let second = ReplayFixtures.stroke(created: 2.5, offsets: halfSeconds)

        let result = timeline(first, second)

        #expect(result.items[1].start == 2.5)
        #expect(result.duration == 4.5)
    }

    @Test func everyPauseIsCappedSeparately() {
        let strokes = (0..<3).map { index in
            ReplayFixtures.stroke(created: Double(index) * 100, offsets: [0, 1])
        }

        let result = GameReplayTimeline(drawing: PKDrawing(strokes: strokes))

        #expect(result.items.map(\.start) == [0, 2, 4])
        #expect(result.duration == 5)
    }

    @Test func customPauseCap() {
        let first = ReplayFixtures.stroke(created: 0, offsets: [0, 1])
        let second = ReplayFixtures.stroke(created: 50, offsets: [0, 1])

        let result = GameReplayTimeline(drawing: PKDrawing(strokes: [first, second]), maxPause: 0.25)

        #expect(result.items[1].start == 1.25)
    }

    @Test func overlappingStrokesKeepTheirOverlap() {
        let first = ReplayFixtures.stroke(created: 0, offsets: [0, 4])
        let second = ReplayFixtures.stroke(created: 1, offsets: [0, 1])
        let third = ReplayFixtures.stroke(created: 100, offsets: [0, 1])

        let result = timeline(first, second, third)

        #expect(result.items.map(\.start) == [0, 1, 5])
        #expect(result.duration == 6)
    }

    @Test func nothingShowsBeforeTheFirstStroke() {
        let result = timeline(ReplayFixtures.stroke(created: 0, offsets: halfSeconds))

        #expect(result.drawing(at: -1).strokes.isEmpty)
    }

    @Test func finishedStrokesAreWholeAndLaterOnesAreMissing() {
        let first = ReplayFixtures.stroke(created: 0, offsets: [0, 1], y: 1)
        let second = ReplayFixtures.stroke(created: 100, offsets: [0, 1], y: 2)
        let result = timeline(first, second)

        let atTwo = result.drawing(at: 1.5)

        #expect(atTwo.strokes.count == 1)
        #expect(atTwo.strokes[0].path.count == 2)
        #expect(result.drawing(at: 2).strokes.count == 2)
        #expect(result.drawing(at: 3).strokes.count == 2)
    }

    @Test func strokeInProgressIsCutAtTheRightPoint() {
        let stroke = ReplayFixtures.stroke(created: 0, offsets: halfSeconds)
        let result = timeline(stroke)

        func pointCount(at time: TimeInterval) -> Int? {
            result.drawing(at: time).strokes.first?.path.count
        }

        #expect(pointCount(at: 0) == 1)
        #expect(pointCount(at: 0.49) == 1)
        #expect(pointCount(at: 0.5) == 2)
        #expect(pointCount(at: 1.2) == 3)
        #expect(pointCount(at: 1.99) == 4)
        #expect(pointCount(at: 2) == 5)
    }

    @Test func strokeInProgressStartsAfterTheCappedPause() {
        let first = ReplayFixtures.stroke(created: 0, offsets: [0, 1])
        let second = ReplayFixtures.stroke(created: 500, offsets: halfSeconds)
        let result = timeline(first, second)

        // The second stroke starts at replay time 2, so 3.2 is 1.2 s into it.
        let strokes = result.drawing(at: 3.2).strokes

        #expect(strokes.map(\.path.count) == [2, 3])
    }

    @Test func partialStrokeKeepsInkTransformMaskAndDate() {
        let ink = PKInk(.marker, color: .systemPink)
        let transform = CGAffineTransform(translationX: 5, y: 7)
        let mask = UIBezierPath(rect: CGRect(x: 100, y: 100, width: 5, height: 5))
        let stroke = ReplayFixtures.stroke(created: 3, offsets: halfSeconds, ink: ink, transform: transform, mask: mask)

        let partial = timeline(stroke).drawing(at: 1).strokes[0]

        #expect(partial.path.count == 3)
        #expect(partial.ink.inkType == .marker)
        #expect(partial.ink.color == stroke.ink.color)
        #expect(partial.transform == transform)
        #expect(partial.mask?.bounds == stroke.mask?.bounds)
        #expect(partial.randomSeed == stroke.randomSeed)
        #expect(partial.path.creationDate == stroke.path.creationDate)
        #expect(partial.path[2].timeOffset == 1)
    }

    @Test func singlePointStrokeAppearsAtOnce() {
        let dot = ReplayFixtures.stroke(created: 0, offsets: [0])
        let result = timeline(dot)

        #expect(result.duration == 0)
        #expect(result.drawing(at: 0).strokes.count == 1)
    }

    @Test func pointTimesThatDoNotStartAtZeroPlayFromTheirFirstPoint() {
        // A piece cut from the middle of a longer stroke.
        let piece = ReplayFixtures.stroke(created: 0, offsets: [2, 2.5, 3])
        let result = timeline(piece)

        #expect(result.items[0].start == 0)
        #expect(result.duration == 1)
        #expect(result.drawing(at: 0.6).strokes[0].path.count == 2)
    }

    // MARK: Pixel eraser

    private static let tolerance = 0.02

    private func erase(_ drawing: PKDrawing, atX x: CGFloat) -> PKDrawing {
        let points = [CGFloat(0), 100].map { y in
            PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: Double(y) / 100,
                size: CGSize(width: 10, height: 10),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let eraser = PKStrokePath(controlPoints: points, creationDate: ReplayFixtures.epoch.addingTimeInterval(60))
        return drawing.erasingPath(eraser)
    }

    /// 11 points, one every half second, 5 points apart in x. Time 5 s.
    private var lineDrawnOverFiveSeconds: PKStroke {
        ReplayFixtures.stroke(created: 5, offsets: (0...10).map { Double($0) / 2 }, y: 50)
    }

    @Test func erasingTheMiddleSplitsTheStrokeIntoPiecesThatKeepTheirTiming() throws {
        let line = lineDrawnOverFiveSeconds
        let erased = erase(PKDrawing(strokes: [line]), atX: 25)
        let roundTripped = try PKDrawing(data: erased.dataRepresentation())

        for drawing in [erased, roundTripped] {
            #expect(drawing.strokes.count == 2)
            for piece in drawing.strokes {
                #expect(piece.path.creationDate == line.path.creationDate)
                #expect(piece.path.count == line.path.count)
                #expect(piece.path.first?.timeOffset == 0)
                #expect(piece.path.last?.timeOffset == 5)
                #expect(piece.mask != nil)
            }
        }
    }

    @Test func piecesPlayOnlyTheirVisiblePartInTheOriginalOrder() throws {
        let erased = erase(PKDrawing(strokes: [lineDrawnOverFiveSeconds]), atX: 25)

        // Reverse the pieces to show the order does not come from the array.
        let result = GameReplayTimeline(drawing: PKDrawing(strokes: erased.strokes.reversed()))

        #expect(result.items.count == 2)
        // The left piece shows the path up to about 1.7 s. The right piece shows
        // it from about 3.3 s, after a 1.6 s hole that is cut to the 1 s cap.
        #expect(abs(result.items[0].start - 0) < Self.tolerance)
        #expect(abs(result.items[0].end - 1.7) < Self.tolerance)
        #expect(abs(result.items[1].start - 2.7) < Self.tolerance)
        #expect(abs(result.items[1].end - 4.4) < Self.tolerance)
        #expect(result.items[0].stroke.maskedPathRanges.map(\.lowerBound) == [0])
        #expect(result.duration < 5)
    }

    @Test func erasedGapShowsNothingNewUntilTheNextPieceStarts() throws {
        let erased = erase(PKDrawing(strokes: [lineDrawnOverFiveSeconds]), atX: 25)
        let result = GameReplayTimeline(drawing: erased)

        let inTheGap = result.drawing(at: 2.2).strokes
        let insideSecondPiece = result.drawing(at: 3.0).strokes
        let atTheEnd = result.drawing(at: result.duration).strokes

        #expect(inTheGap.count == 1)
        #expect(inTheGap[0].path.count == 11)
        #expect(insideSecondPiece.count == 2)
        // 3.0 s is 0.3 s into the second piece, which is at 3.3 s + 0.3 s = 3.6 s of the path.
        #expect(insideSecondPiece[1].path.count == 8)
        #expect(atTheEnd.count == 2)
        #expect(atTheEnd.allSatisfy { $0.path.count == 11 })
    }

    @Test func erasedStartOfAStrokeIsNotWaitedFor() throws {
        let erased = erase(PKDrawing(strokes: [lineDrawnOverFiveSeconds]), atX: 2)
        let result = GameReplayTimeline(drawing: erased)

        #expect(erased.strokes.count == 1)
        // The visible part starts at path position 2, which is time 1.
        #expect(result.items[0].start == 0)
        #expect(abs(result.duration - 4) < Self.tolerance)
        // Time 0.5 of the replay is time 1.5 of the stroke: 4 points.
        #expect(result.drawing(at: 0.5).strokes[0].path.count == 4)
    }

    @Test func erasedEndOfAStrokeIsNotWaitedFor() throws {
        let erased = erase(PKDrawing(strokes: [lineDrawnOverFiveSeconds]), atX: 46)

        let result = GameReplayTimeline(drawing: erased)

        #expect(abs(result.duration - 3.8) < Self.tolerance)
    }

    @Test func maskedStrokeWithoutAnEraserPlaysItsVisiblePart() {
        let mask = UIBezierPath(rect: CGRect(x: -3, y: 40, width: 20, height: 20))
        let stroke = ReplayFixtures.stroke(created: 0, offsets: (0...10).map { Double($0) / 2 }, y: 50, mask: mask)

        let result = timeline(stroke)

        #expect(!stroke.maskedPathRanges.isEmpty)
        #expect(result.duration > 1)
        #expect(result.duration < 2.5)
    }

    @Test func partialAndFinalStrokesKeepTheMaskTransformInkAndCreationDate() throws {
        let mask = UIBezierPath(rect: CGRect(x: -3, y: 0, width: 20, height: 200))
        let original = ReplayFixtures.stroke(
            created: 3,
            offsets: (0...10).map { Double($0) / 2 },
            y: 50,
            ink: PKInk(.pencil, color: .blue),
            transform: CGAffineTransform(translationX: 0, y: 10),
            mask: mask
        )
        let result = timeline(original)
        try #require(!original.maskedPathRanges.isEmpty)

        let partial = try #require(result.drawing(at: 0.5).strokes.first)
        let final = try #require(result.drawing(at: result.duration).strokes.first)

        #expect(partial.path.count < original.path.count)
        #expect(final.path.count == original.path.count)
        for stroke in [partial, final] {
            #expect(stroke.mask?.cgPath == original.mask?.cgPath)
            #expect(stroke.transform == original.transform)
            #expect(stroke.ink.inkType == original.ink.inkType)
            #expect(stroke.ink.color == original.ink.color)
            #expect(stroke.path.creationDate == original.path.creationDate)
            #expect(stroke.randomSeed == original.randomSeed)
        }
    }

    @Test func piecesThatShareACreationDateAndOffsetsStartTogetherWhenNothingIsMasked() {
        let firstPiece = ReplayFixtures.stroke(created: 0, offsets: [0, 1, 2], y: 1)
        let secondPiece = ReplayFixtures.stroke(created: 0, offsets: [0, 1, 2], y: 2)

        let result = timeline(secondPiece, firstPiece)

        // Equal in time, so they keep their order in the drawing.
        #expect(result.items.map { $0.stroke.path[0].location.y } == [2, 1])
        #expect(result.items.map(\.start) == [0, 0])
    }
}
