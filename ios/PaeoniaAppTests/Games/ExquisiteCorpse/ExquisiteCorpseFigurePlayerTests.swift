import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// A wall clock the test moves by hand.
private nonisolated final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wall: TimeInterval = 100

    func now() -> TimeInterval {
        lock.withLock { wall }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { wall += seconds }
    }
}

@MainActor
struct ExquisiteCorpseFigurePlayerTests {
    private typealias Part = ExquisiteCorpsePartKind

    /// A drawing with one stroke that takes `seconds` to draw.
    private func drawing(seconds: TimeInterval) -> PKDrawing {
        ReplayFixtures.drawing(ReplayFixtures.stroke(created: 0, offsets: [0, seconds]))
    }

    /// A drawing of two strokes, one after the other, with `first` and `second` seconds each.
    private func twoStrokes(first: TimeInterval, second: TimeInterval) -> PKDrawing {
        ReplayFixtures.drawing(
            ReplayFixtures.stroke(created: 0, offsets: [0, first]),
            ReplayFixtures.stroke(created: first, offsets: [0, second])
        )
    }

    /// A player with the drawings loaded, a clock the test moves, and a log of the
    /// haptics and the reports.
    @MainActor
    private final class Harness {
        private final class Log {
            var selections = 0
            var reported: [ExquisiteCorpsePartKind] = []
        }

        let clock: StepClock
        let player: ExquisiteCorpseFigurePlayer
        private let log: Log

        var selections: Int { log.selections }
        var reported: [ExquisiteCorpsePartKind] { log.reported }

        init(_ drawings: [ExquisiteCorpsePartKind: PKDrawing]) {
            let clock = StepClock()
            let log = Log()
            player = ExquisiteCorpseFigurePlayer(monotonicNow: { clock.now() }, selection: { log.selections += 1 })
            self.clock = clock
            self.log = log
            player.load(drawings)
            player.onPartFinished = { log.reported.append($0) }
        }

        func isFinished(_ part: ExquisiteCorpsePartKind) -> Bool {
            player.isFinished(part, atWall: clock.now())
        }
    }

    private func harness(head: TimeInterval = 2, body: TimeInterval = 2, legs: TimeInterval = 2) -> Harness {
        Harness([.head: drawing(seconds: head), .body: drawing(seconds: body), .legs: drawing(seconds: legs)])
    }

    // MARK: Rate

    @Test func aShortPartPlaysAtItsOwnPace() {
        let rig = harness(head: 2)
        rig.player.start(.head)

        rig.clock.advance(1.9)
        #expect(!rig.isFinished(.head))
        rig.clock.advance(0.1)
        #expect(rig.isFinished(.head))
    }

    @Test func aLongPartPlaysFasterToFitInTwoAndAHalfSeconds() {
        let rig = harness(head: 10)
        rig.player.start(.head)

        rig.clock.advance(2.4)
        #expect(!rig.isFinished(.head))
        rig.clock.advance(0.1)
        #expect(rig.isFinished(.head))
    }

    @Test func everyPartHasItsOwnRate() {
        // The head is squeezed into 2.5 seconds, and the shorter parts take their own time.
        let rig = harness(head: 10, body: 2, legs: 1)
        for part in Part.allCases {
            rig.player.start(part)
        }

        rig.clock.advance(1)
        #expect(rig.isFinished(.legs))
        #expect(!rig.isFinished(.body))
        rig.clock.advance(1)
        #expect(rig.isFinished(.body))
        #expect(!rig.isFinished(.head))
        rig.clock.advance(0.5)
        #expect(rig.isFinished(.head))
    }

    @Test func aPartShowsTheStrokesDrawnSoFar() {
        // 10 seconds in all, so it plays at 4x. After 0.75 seconds the first stroke is half
        // drawn and the second has not started. After 1.25 seconds the second has begun.
        let drawing = twoStrokes(first: 4, second: 6)
        let rig = Harness([.head: drawing, .body: drawing, .legs: drawing])
        rig.player.start(.head)

        rig.clock.advance(0.75)
        #expect(rig.player.drawing(for: .head, atWall: rig.clock.now(), side: 320)?.strokes.count == 1)
        rig.clock.advance(0.5)
        #expect(rig.player.drawing(for: .head, atWall: rig.clock.now(), side: 320)?.strokes.count == 2)
    }

    // MARK: Waiting

    @Test func aPartThatHasNotStartedShowsNothing() {
        let rig = harness()

        #expect(rig.player.drawing(for: .body, atWall: rig.clock.now(), side: 320) == nil)
        #expect(!rig.isFinished(.body))
    }

    @Test func aPartThatIsNotLoadedShowsNothingAndNeverStarts() {
        let rig = Harness([.head: drawing(seconds: 2)])

        rig.player.start(.body)

        #expect(rig.player.playingPart == nil)
        #expect(rig.player.drawing(for: .body, atWall: rig.clock.now(), side: 320) == nil)
        #expect(!rig.isFinished(.body))
    }

    // MARK: Hold to fast-forward

    @Test func holdingPlaysAtFourTimesOnTopOfThePartsRate() {
        // 10 seconds plays at 4x, and a hold makes it 16x. One second in, 4 seconds
        // are drawn and 6 are left, which take 0.375 seconds at 16x.
        let rig = harness(head: 10)
        rig.player.start(.head)
        rig.clock.advance(1)
        rig.player.setFastForward(true)

        rig.clock.advance(0.37)
        #expect(!rig.isFinished(.head))
        rig.clock.advance(0.01)
        #expect(rig.isFinished(.head))
    }

    @Test func releasingGoesBackToThePartsOwnRate() {
        // A 1 second part plays at 1x. A hold for 0.1 seconds draws 0.4 of it.
        let rig = harness(head: 1)
        rig.player.start(.head)
        rig.player.setFastForward(true)
        rig.clock.advance(0.1)
        rig.player.setFastForward(false)

        // 0.6 seconds are left at 1x.
        rig.clock.advance(0.59)
        #expect(!rig.isFinished(.head))
        rig.clock.advance(0.02)
        #expect(rig.isFinished(.head))
    }

    @Test func theHoldHapticFiresOncePerPress() {
        let rig = harness()
        rig.player.start(.head)

        rig.player.setFastForward(true)
        rig.player.setFastForward(true)
        #expect(rig.selections == 1)
        #expect(rig.player.isFastForwarding)

        rig.player.setFastForward(false)
        rig.player.setFastForward(false)
        #expect(rig.selections == 1)
        #expect(!rig.player.isFastForwarding)

        rig.player.setFastForward(true)
        #expect(rig.selections == 2)
    }

    @Test func aHoldCarriesOverToThePartThatStartsNext() {
        // A 2 second part at 4x takes half a second.
        let rig = harness(head: 2, body: 2)
        rig.player.start(.head)
        rig.player.setFastForward(true)
        rig.clock.advance(0.5)
        #expect(rig.isFinished(.head))

        rig.player.start(.body)
        rig.clock.advance(0.49)
        #expect(!rig.isFinished(.body))
        rig.clock.advance(0.02)
        #expect(rig.isFinished(.body))
    }

    // MARK: Finish

    @Test func finishShowsEveryPartInFullWithoutReporting() {
        let drawing = twoStrokes(first: 2, second: 2)
        let rig = Harness([.head: drawing, .body: drawing, .legs: drawing])
        rig.player.start(.head)
        rig.player.setFastForward(true)

        rig.player.finish()

        for part in Part.allCases {
            #expect(rig.player.drawing(for: part, atWall: rig.clock.now(), side: 320)?.strokes.count == 2)
            #expect(rig.isFinished(part))
        }
        #expect(rig.player.playingPart == nil)
        #expect(!rig.player.isFastForwarding)
        #expect(rig.reported.isEmpty)
    }

    // MARK: Reports

    @Test func theFinishOfAPartIsReportedOnce() {
        let rig = harness(head: 2)
        rig.player.start(.head)
        #expect(rig.reported.isEmpty)

        rig.clock.advance(2)
        #expect(rig.isFinished(.head))
        #expect(rig.isFinished(.head))
        rig.clock.advance(5)
        #expect(rig.isFinished(.head))

        #expect(rig.reported == [.head])
        #expect(rig.player.playingPart == nil)
    }

    @Test func aPartThatStartsAgainIsReportedAgain() {
        let rig = harness(head: 1)
        rig.player.start(.head)
        rig.clock.advance(1)
        #expect(rig.isFinished(.head))

        rig.player.start(.head)
        #expect(!rig.isFinished(.head))
        rig.clock.advance(1)
        #expect(rig.isFinished(.head))

        #expect(rig.reported == [.head, .head])
    }

    @Test func anEmptyDrawingFinishesAtOnce() {
        let rig = Harness([.head: PKDrawing(), .body: drawing(seconds: 2), .legs: drawing(seconds: 2)])

        rig.player.start(.head)

        #expect(rig.reported == [.head])
        #expect(rig.player.playingPart == nil)
        #expect(rig.isFinished(.head))
        #expect(rig.reported == [.head])
    }

    @Test func thePartThatPlaysIsTheOneStartedLast() {
        let rig = harness()

        rig.player.start(.head)
        #expect(rig.player.playingPart == .head)
        #expect(rig.player.isPlaying)

        rig.clock.advance(2)
        #expect(rig.isFinished(.head))
        #expect(rig.player.playingPart == nil)
        #expect(!rig.player.isPlaying)
    }

    // MARK: Play again

    @Test func playingInSequenceStartsEachPartWhenTheOneBeforeItEnds() {
        let rig = harness(head: 1, body: 1, legs: 1)
        rig.player.finish()

        rig.player.playInSequence()
        #expect(rig.player.playingPart == .head)
        // The parts that wait show nothing.
        #expect(rig.player.drawing(for: .body, atWall: rig.clock.now(), side: 320) == nil)

        rig.clock.advance(1)
        #expect(rig.isFinished(.head))
        #expect(rig.player.playingPart == .body)
        rig.clock.advance(1)
        #expect(rig.isFinished(.body))
        #expect(rig.player.playingPart == .legs)
        rig.clock.advance(1)
        #expect(rig.isFinished(.legs))

        #expect(rig.player.playingPart == nil)
        #expect(rig.reported == [.head, .body, .legs])
    }

    @Test func resetBlanksThePartsAndGivesTheCanvasesNewIDs() {
        let rig = harness()
        rig.player.finish()
        let generation = rig.player.generation

        rig.player.reset()

        #expect(rig.player.generation == generation + 1)
        for part in Part.allCases {
            #expect(rig.player.drawing(for: part, atWall: rig.clock.now(), side: 320) == nil)
        }
    }
}
