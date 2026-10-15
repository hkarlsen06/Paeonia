import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// The split of a replay into finished strokes and strokes in progress, and the
/// timeline scaled to a canvas.
struct GameReplayProgressTests {
    private func timeline() -> GameReplayTimeline {
        let first = ReplayFixtures.stroke(created: 0, offsets: [0, 1, 2], y: 10)
        let second = ReplayFixtures.stroke(created: 2, offsets: [0, 1, 2], y: 20)
        return GameReplayTimeline(drawing: PKDrawing(strokes: [first, second]))
    }

    @Test func nothingHasStartedBeforeTheFirstStroke() {
        let progress = timeline().progress(at: -1)

        #expect(progress.finishedCount == 0)
        #expect(progress.partials.isEmpty)
    }

    @Test func aStrokeInProgressIsCutAtThePointsDrawnSoFar() throws {
        let progress = timeline().progress(at: 1.5)

        #expect(progress.finishedCount == 0)
        let partial = try #require(progress.partials.first)
        #expect(partial.index == 0)
        #expect(partial.stroke.path.count == 2)
    }

    @Test func aFinishedStrokeCountsAndTheNextOneIsInProgress() {
        let timeline = timeline()
        let progress = timeline.progress(at: 3)

        #expect(progress.finishedCount == 1)
        #expect(progress.partials.map(\.index) == [1])
        #expect(timeline.finishedStrokes(at: 3).count == 1)
    }

    @Test func everythingIsFinishedAtTheEnd() {
        let timeline = timeline()
        let progress = timeline.progress(at: timeline.duration)

        #expect(progress.finishedCount == 2)
        #expect(progress.partials.isEmpty)
        #expect(timeline.finishedStrokes(at: timeline.duration).count == 2)
    }

    @Test func finishedAndInProgressStrokesMatchTheWholeDrawing() {
        let timeline = timeline()
        for time in stride(from: 0.0, through: timeline.duration, by: 0.5) {
            let progress = timeline.progress(at: time)
            let whole = timeline.drawing(at: time).strokes

            #expect(progress.finishedCount + progress.partials.count == whole.count)
        }
    }

    @Test func aFittedTimelineKeepsTheTimesAndTheIdentity() {
        let original = timeline()
        let fitted = original.fitted(toSide: GameCanvas.canonicalSide * 2)

        #expect(fitted.id == original.id)
        #expect(fitted.duration == original.duration)
        #expect(fitted.items.map(\.start) == original.items.map(\.start))
        #expect(fitted.items.map(\.end) == original.items.map(\.end))
    }

    @Test func aFittedTimelineScalesTheStrokes() {
        let original = timeline()
        let fitted = original.fitted(toSide: GameCanvas.canonicalSide * 2)

        let before = original.finishedStrokes(at: original.duration)[0].renderBounds
        let after = fitted.finishedStrokes(at: fitted.duration)[0].renderBounds
        #expect(abs(after.maxX - before.maxX * 2) < 6)
    }

    @Test func eachTimelineHasItsOwnIdentity() {
        #expect(timeline().id != timeline().id)
    }
}
