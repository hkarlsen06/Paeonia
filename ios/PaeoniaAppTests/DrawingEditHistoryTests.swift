import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// Undo that keeps the partner's strokes, and the paint bucket.
struct DrawingEditHistoryTests {
    @Test func undoTakesBackOnlyThisPersonsStepAndKeepsThePartnersStroke() throws {
        var history = DrawingEditHistory()
        let first = line(at: 20)
        let mine = line(at: 80)
        let partners = line(at: 140)

        history.record(from: PKDrawing(strokes: [first]), to: PKDrawing(strokes: [first, mine]))
        // The partner's stroke arrives without a step of its own.
        let withPartner = PKDrawing(strokes: [first, mine, partners])

        let undoneResult = history.undo(withPartner)
        let undone = try #require(undoneResult)
        #expect(keys(undone.strokes) == keys([first, partners]))

        let redoneResult = history.redo(undone)
        let redone = try #require(redoneResult)
        #expect(redone.strokes.count == 3)
        #expect(!history.canRedo)
    }

    @Test func undoingARemovalPutsTheStrokeBackOnItsLayer() throws {
        var history = DrawingEditHistory()
        let strokes = [line(at: 20), line(at: 80), line(at: 140)]
        let erased = PKDrawing(strokes: [strokes[0], strokes[2]])
        history.record(from: PKDrawing(strokes: strokes), to: erased)

        let undoneResult = history.undo(erased)
        let undone = try #require(undoneResult)
        #expect(keys(undone.strokes) == keys(strokes))
    }

    @Test func aNewStepDropsRedoAndNoChangeIsNoStep() {
        var history = DrawingEditHistory()
        let drawing = PKDrawing(strokes: [line(at: 20)])
        history.record(from: drawing, to: drawing)
        #expect(!history.canUndo)

        history.record(from: PKDrawing(), to: drawing)
        _ = history.undo(drawing)
        history.record(from: PKDrawing(), to: PKDrawing(strokes: [line(at: 80)]))
        #expect(!history.canRedo)
        #expect(history.canUndo)
    }

    @Test(arguments: [100, 200])
    func undoingASecondPixelEraseRestoresOnlyThatErase(firstEraseX: Int) throws {
        var history = DrawingEditHistory()
        let secondEraseX = 300 - firstEraseX
        let original = longLine()
        let erasedOnce = erase(original, at: CGFloat(firstEraseX))
        let erasedTwice = erase(erasedOnce, at: CGFloat(secondEraseX))
        #expect(render(erasedOnce).pixel(x: firstEraseX, y: 100).alpha == 0)
        #expect(render(erasedOnce).pixel(x: secondEraseX, y: 100).alpha > 200)
        #expect(render(erasedTwice).pixel(x: secondEraseX, y: 100).alpha == 0)
        history.record(from: original, to: erasedOnce)
        history.record(from: erasedOnce, to: erasedTwice)

        let undoneResult = history.undo(erasedTwice)
        let undone = try #require(undoneResult)
        #expect(render(undone).pixel(x: firstEraseX, y: 100).alpha == 0)
        #expect(render(undone).pixel(x: secondEraseX, y: 100).alpha > 200)
        #expect(render(undone).pixel(x: 40, y: 100).alpha > 200)
        let redoneResult = history.redo(undone)
        let redone = try #require(redoneResult)
        #expect(render(redone).pixel(x: 100, y: 100).alpha == 0)
        #expect(render(redone).pixel(x: 200, y: 100).alpha == 0)
        #expect(render(redone).pixel(x: 140, y: 100).alpha > 200)
    }

    @Test func liveChangesKeepBothSidesOfAPixelErase() throws {
        let original = longLine()
        let erased = erase(original, at: 100)
        var tracker = WidgetLiveStrokeTracker()
        tracker.reset(to: original)
        let changes = tracker.changes(to: erased)
        let received = WidgetLiveStrokeSync.apply(upserts: changes.upserts, removals: changes.removals, to: original)
        let decoded = try PKDrawing(data: received.dataRepresentation())

        #expect(render(decoded).pixel(x: 100, y: 100).alpha == 0)
        #expect(render(decoded).pixel(x: 40, y: 100).alpha > 200)
        #expect(render(decoded).pixel(x: 200, y: 100).alpha > 200)
    }

    // MARK: Fill

    @Test func fillInsideABoxStaysInsideIt() throws {
        let box = PKDrawing(strokes: [boxOutline(from: 100, to: 200)])
        let fill = DrawingFloodFill.fillStroke(in: box, side: 320, at: CGPoint(x: 150, y: 150), color: .red)
        let stroke = try #require(fill)
        let filled = PKDrawing(strokes: box.strokes + [stroke])

        let image = render(filled)
        #expect(isRed(image.pixel(x: 150, y: 150)))
        #expect(isRed(image.pixel(x: 110, y: 190)))
        #expect(image.pixel(x: 50, y: 50).alpha == 0)
        #expect(image.pixel(x: 250, y: 150).alpha == 0)
        // It survives saving and loading, like a drawn stroke.
        let reloaded = try PKDrawing(data: filled.dataRepresentation())
        #expect(isRed(render(reloaded).pixel(x: 150, y: 150)))
    }

    @Test func fillOutsideTheBoxLeavesTheInsideEmpty() throws {
        let box = PKDrawing(strokes: [boxOutline(from: 100, to: 200)])
        let fill = DrawingFloodFill.fillStroke(in: box, side: 320, at: CGPoint(x: 20, y: 20), color: .red)
        let stroke = try #require(fill)

        let image = render(PKDrawing(strokes: box.strokes + [stroke]))
        #expect(isRed(image.pixel(x: 20, y: 20)))
        #expect(isRed(image.pixel(x: 300, y: 300)))
        #expect(image.pixel(x: 150, y: 150).alpha == 0)
    }
}

private func keys(_ strokes: [PKStroke]) -> [String] {
    strokes.map(WidgetLiveStrokeSync.key(for:))
}

private func longLine() -> PKDrawing {
    let locations = stride(from: 20, through: 300, by: 10).map { CGPoint(x: $0, y: 100) }
    return PKDrawing(strokes: [stroke(through: locations, createdAt: 1)])
}

private func erase(_ drawing: PKDrawing, at x: CGFloat) -> PKDrawing {
    let points = [80, 100, 120].enumerated().map { index, y in
        PKStrokePoint(
            location: CGPoint(x: x, y: CGFloat(y)), timeOffset: Double(index) * 0.01,
            size: CGSize(width: 20, height: 20), opacity: 1,
            force: 1, azimuth: 0, altitude: .pi / 2
        )
    }
    return drawing.erasingPath(PKStrokePath(controlPoints: points, creationDate: .now))
}

private func line(at origin: CGFloat) -> PKStroke {
    stroke(through: [CGPoint(x: origin, y: origin), CGPoint(x: origin + 10, y: origin + 10)], createdAt: origin)
}

private func boxOutline(from low: CGFloat, to high: CGFloat) -> PKStroke {
    let corners = [
        CGPoint(x: low, y: low), CGPoint(x: high, y: low), CGPoint(x: high, y: high),
        CGPoint(x: low, y: high), CGPoint(x: low, y: low),
    ]
    // Many points per side, so the path stays on the box's edges.
    let points = zip(corners, corners.dropFirst()).flatMap { start, end in
        (0..<20).map { step in
            let progress = CGFloat(step) / 20
            return CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
        }
    } + [corners[0]]
    return stroke(through: points, createdAt: 1)
}

private func stroke(through locations: [CGPoint], createdAt: CGFloat) -> PKStroke {
    let points = locations.enumerated().map { index, location in
        PKStrokePoint(
            location: location,
            timeOffset: TimeInterval(index) * 0.01,
            size: CGSize(width: 4, height: 4),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )
    }
    let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + createdAt)
    let path = PKStrokePath(controlPoints: points, creationDate: createdAt)
    return PKStroke(ink: PKInk(.monoline, color: .black), path: path)
}

private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private struct RenderedPixels {
    let bytes: [UInt8]
    let side: Int

    func pixel(x: Int, y: Int) -> Pixel {
        let offset = (y * side + x) * 4
        return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
    }
}

private func render(_ drawing: PKDrawing) -> RenderedPixels {
    let side = 320
    let image = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 1)
    var bytes = [UInt8](repeating: 0, count: side * side * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        if let cgImage = image.cgImage {
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
    return RenderedPixels(bytes: bytes, side: side)
}

private func isRed(_ pixel: Pixel) -> Bool {
    pixel.red > 200 && pixel.green < 60 && pixel.blue < 60 && pixel.alpha > 200
}
