import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// The strip the next drawer sees: the part clipped at the fold.
struct ExquisiteCorpseFoldTests {
    private typealias Fold = ExquisiteCorpseFold

    private var fold: CGFloat { Fold.foldY() }

    private func stroke(
        _ locations: [CGPoint],
        ink: PKInk = PKInk(.pen, color: .black),
        transform: CGAffineTransform = .identity,
        mask: UIBezierPath? = nil
    ) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: ink,
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 1_000)),
            transform: transform,
            mask: mask
        )
    }

    /// A vertical line at x = 50 whose control points are `spacing` apart.
    private func vertical(from startY: CGFloat, spacing: CGFloat, count: Int = 11) -> [CGPoint] {
        (0..<count).map { CGPoint(x: 50, y: startY + CGFloat($0) * spacing) }
    }

    private func locations(_ stroke: PKStroke) -> [CGPoint] {
        (0..<stroke.path.count).map { stroke.path[$0].location }
    }

    private func strip(_ strokes: PKStroke...) -> PKDrawing {
        Fold.strip(of: PKDrawing(strokes: strokes))
    }

    private func near(_ value: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        abs(value - expected) < tolerance
    }

    // MARK: Whole strokes

    @Test func aStrokeAboveTheFoldIsDropped() {
        let above = stroke(vertical(from: 20, spacing: 10))

        #expect(strip(above).strokes.isEmpty)
    }

    @Test func aStrokeBelowTheFoldIsKeptAsItIs() {
        let below = stroke([CGPoint(x: 10, y: 290), CGPoint(x: 100, y: 300), CGPoint(x: 150, y: 310)])

        let result = strip(below)

        #expect(result.strokes.count == 1)
        #expect(locations(result.strokes[0]) == locations(below))
        #expect(result.strokes[0].path.creationDate == below.path.creationDate)
    }

    // MARK: Crossing strokes

    @Test func aStrokeGoingDownStartsExactlyOnTheFold() {
        // y = 200, 212, ... 320. The fold at 281.6 lies between the control points 6 and 7.
        let crossing = stroke(vertical(from: 200, spacing: 12))

        let result = strip(crossing)

        #expect(result.strokes.count == 1)
        let points = locations(result.strokes[0])
        #expect(points.count == 5)
        for (point, expected) in zip(points, [fold, 284, 296, 308, 320]) {
            #expect(near(point.y, expected))
            #expect(point.x == 50)
        }
        // The interpolated point carries the stroke's other values along.
        #expect(near(result.strokes[0].path[0].size.width, 4))
        #expect(near(result.strokes[0].path[0].opacity, 1))
    }

    @Test func aStrokeGoingUpEndsExactlyOnTheFold() {
        let crossing = stroke(vertical(from: 320, spacing: -12))

        let points = locations(strip(crossing).strokes[0])

        #expect(points.count == 5)
        #expect(near(points[0].y, 320))
        #expect(near(points[points.count - 1].y, fold))
    }

    @Test func aStrokeThatCrossesSeveralTimesGivesOneStrokePerRunBelow() {
        // A wave around the fold. It starts below, rises across, dips below twice and ends below.
        let wave = stroke((0..<100).map { index in
            let x = 10 + CGFloat(index) * 3
            return CGPoint(x: x, y: fold + 25 * CGFloat(sin(Double(x) * 0.05)))
        })

        let result = strip(wave).strokes

        #expect(result.count == 3)
        let runs = result.map(locations)
        // The first run begins where the wave begins and ends on the fold.
        #expect(runs[0][0] == locations(wave)[0])
        #expect(near(runs[0][runs[0].count - 1].y, fold))
        // The middle run starts and ends on the fold.
        #expect(near(runs[1][0].y, fold) && near(runs[1][runs[1].count - 1].y, fold))
        // The last run starts on the fold and ends where the wave ends.
        #expect(near(runs[2][0].y, fold))
        #expect(runs[2][runs[2].count - 1] == locations(wave)[99])
        // Nothing of any run lies above the fold, apart from rounding.
        #expect(runs.joined().allSatisfy { $0.y >= fold - 0.001 })
        // Along the wave, the runs follow each other left to right.
        #expect(runs[0][0].x < runs[1][0].x && runs[1][0].x < runs[2][0].x)
    }

    // MARK: Ink, transform and mask

    @Test func theTransformDecidesWhichSideTheStrokeIsOn() {
        // In stroke space y runs 0 to 100. Moved down by 250, the stroke spans 250 to 350.
        let moved = stroke(vertical(from: 0, spacing: 10), transform: CGAffineTransform(translationX: 0, y: 250))

        let result = strip(moved).strokes[0]

        #expect(result.transform == moved.transform)
        let points = locations(result)
        // The fold is at 31.6 in stroke space.
        #expect(near(points[0].y, fold - 250))
        #expect(near(points[0].applying(result.transform).y, fold))
        #expect(near(points[points.count - 1].y, 100))
    }

    @Test func erasedInkAboveAndBelowTheFoldIsNotInTheStrip() {
        // The eraser hid y from 290 to 300. The mask shows everything else.
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 320, height: 290))
        mask.append(UIBezierPath(rect: CGRect(x: 0, y: 300, width: 320, height: 20)))
        let erased = stroke(vertical(from: 200, spacing: 12), mask: mask)

        let result = strip(erased).strokes

        #expect(result.count == 2)
        let runs = result.map(locations)
        #expect(near(runs[0][0].y, fold))
        #expect(near(runs[0][runs[0].count - 1].y, 290, tolerance: 0.5))
        #expect(near(runs[1][0].y, 300, tolerance: 0.5))
        #expect(near(runs[1][runs[1].count - 1].y, 320))
        #expect(runs.joined().allSatisfy { $0.y <= 290.5 || $0.y >= 299.5 })
        #expect(result.allSatisfy { $0.mask != nil })
    }

}

/// Paint bucket fills and erased strokes carry a mask, and no part of it may
/// reach above the fold.
extension ExquisiteCorpseFoldTests {
    // MARK: Masks and fills

    /// A paint bucket fill as `DrawingFloodFill` makes one: a line through the
    /// middle of `area`, wide enough to cover it, with the area as its mask.
    private func fill(_ area: CGRect) -> PKStroke {
        let width = max(area.width, area.height) + 2
        let points = [area.minX, area.maxX].map { x in
            PKStrokePoint(
                location: CGPoint(x: x, y: area.midY),
                timeOffset: 0,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.monoline, color: .systemPink),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 1_000)),
            transform: .identity,
            mask: UIBezierPath(rect: area)
        )
    }

    /// PencilKit keeps masks in single precision, so the fold at 281.6 can read as 281.59.
    private func isInsideStrip(_ rect: CGRect) -> Bool {
        rect.minY >= fold - 0.1 && rect.maxY <= GameCanvas.canonicalSide + 0.1
    }

    @Test func aFillOfTheWholeCanvasKeepsOnlyItsStrip() throws {
        let whole = DrawingFloodFill.fillStroke(
            in: PKDrawing(),
            side: GameCanvas.canonicalSide,
            at: CGPoint(x: 160, y: 160),
            color: .systemPink
        )
        let result = strip(try #require(whole)).strokes

        // The fill's line runs through y = 160, above the fold, and its ink still covers the strip.
        #expect(result.count == 1)
        let mask = try #require(result.first?.mask)
        #expect(isInsideStrip(mask.bounds))
        #expect(result[0].path.allSatisfy { $0.location.y >= fold })
    }

    @Test func aFillReachingAboveTheFoldLeavesNoShapeAboveIt() throws {
        let area = CGRect(x: 40, y: 200, width: 200, height: 120)
        let result = strip(fill(area)).strokes

        #expect(result.count == 1)
        let mask = try #require(result.first?.mask)
        #expect(isInsideStrip(mask.bounds))
        #expect(near(mask.bounds.minX, 40) && near(mask.bounds.maxX, 240))
        #expect(result[0].path.allSatisfy { $0.location.y >= fold })
    }

    @Test func anErasedStrokeKeepsNoMaskOutlineAboveTheFold() {
        // The mask is the outline of the whole stroke, from y = 100 down.
        let mask = UIBezierPath(rect: CGRect(x: 46, y: 100, width: 8, height: 220))
        let erased = stroke(vertical(from: 100, spacing: 22), mask: mask)

        let result = strip(erased).strokes

        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.mask.map { isInsideStrip($0.bounds) } ?? false })
    }

    @Test func noStoredPointOfAPieceIsAboveTheFold() {
        // The curve dips below the fold between control points that zig-zag across it,
        // so a piece starts with control points above the fold unless they move.
        let zigzag = stroke([
            CGPoint(x: 10, y: 300), CGPoint(x: 40, y: 275), CGPoint(x: 70, y: 310),
            CGPoint(x: 100, y: 273), CGPoint(x: 130, y: 307), CGPoint(x: 160, y: 276),
            CGPoint(x: 190, y: 315), CGPoint(x: 220, y: 279), CGPoint(x: 250, y: 318),
        ])

        let pieces = strip(zigzag).strokes

        #expect(!pieces.isEmpty)
        #expect(pieces.allSatisfy { piece in piece.path.allSatisfy { $0.location.y >= fold - 0.001 } })
    }
}
