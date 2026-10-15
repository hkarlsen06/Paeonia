import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// The cached strip is the strip of the whole canvas, every time.
@MainActor
struct ExquisiteCorpseStripCacheTests {
    private let side: CGFloat = 400

    /// A stroke across the fold, one above it and one below it, on a canvas of `side`.
    private func strokes() -> [PKStroke] {
        let fold = ExquisiteCorpseFold.foldY(side: side)
        return [
            ReplayFixtures.stroke(created: 0, offsets: [0, 1, 2], y: fold + 20),
            ReplayFixtures.stroke(created: 1, offsets: [0, 1, 2], y: 10),
            ReplayFixtures.stroke(created: 2, offsets: [0, 1, 2], y: fold + 5)
        ]
    }

    private func wholeStrip(of strokes: [PKStroke]) -> PKDrawing {
        ExquisiteCorpseFold.strip(of: GameCanvas.canonical(PKDrawing(strokes: strokes), fromSide: side))
    }

    @Test func theStripMatchesTheStripOfTheWholeDrawing() {
        var cache = ExquisiteCorpseStripCache()
        let strokes = strokes()

        let strip = cache.strip(of: strokes, including: nil, fromSide: side)

        #expect(strip.paeoniaContentSignature == wholeStrip(of: strokes).paeoniaContentSignature)
        #expect(strip.strokes.count == 2)
    }

    @Test func aSecondAskGivesTheSameStrip() {
        var cache = ExquisiteCorpseStripCache()
        let strokes = strokes()

        let first = cache.strip(of: strokes, including: nil, fromSide: side)
        let second = cache.strip(of: strokes, including: nil, fromSide: side)

        #expect(first.paeoniaContentSignature == second.paeoniaContentSignature)
    }

    @Test func theStrokeBeingDrawnIsPartOfTheStripButNotRemembered() {
        var cache = ExquisiteCorpseStripCache()
        let strokes = strokes()
        let fold = ExquisiteCorpseFold.foldY(side: side)
        let live = ReplayFixtures.stroke(created: 3, offsets: [0, 1, 2], y: fold + 30)

        let withLive = cache.strip(of: strokes, including: live, fromSide: side)
        let without = cache.strip(of: strokes, including: nil, fromSide: side)

        #expect(withLive.paeoniaContentSignature == wholeStrip(of: strokes + [live]).paeoniaContentSignature)
        #expect(without.paeoniaContentSignature == wholeStrip(of: strokes).paeoniaContentSignature)
    }

    @Test func anErasedStrokeLeavesTheStrip() {
        var cache = ExquisiteCorpseStripCache()
        var strokes = strokes()
        _ = cache.strip(of: strokes, including: nil, fromSide: side)

        strokes.removeFirst()
        let strip = cache.strip(of: strokes, including: nil, fromSide: side)

        #expect(strip.paeoniaContentSignature == wholeStrip(of: strokes).paeoniaContentSignature)
    }

    @Test func aNewCanvasSizeScalesAgain() {
        var cache = ExquisiteCorpseStripCache()
        let strokes = strokes()
        _ = cache.strip(of: strokes, including: nil, fromSide: side)

        let strip = cache.strip(of: strokes, including: nil, fromSide: side * 2)

        let scaled = GameCanvas.canonical(PKDrawing(strokes: strokes), fromSide: side * 2)
        let expected = ExquisiteCorpseFold.strip(of: scaled)
        #expect(strip.paeoniaContentSignature == expected.paeoniaContentSignature)
    }
}
