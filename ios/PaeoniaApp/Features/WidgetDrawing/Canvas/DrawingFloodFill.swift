import PencilKit
import UIKit

/// The paint bucket. PencilKit has no fill, so a fill is one ordinary stroke:
/// a wide line across the filled area's bounds, clipped by a mask to the area
/// itself. It saves, syncs, erases, and undoes like any other stroke.
///
/// The pixel work runs on the main thread when the person taps, and in debug
/// builds too, so it uses plain loops over raw memory. Written with arrays,
/// closures, and sets, one fill took over two seconds on an iPad in a debug build.
nonisolated enum DrawingFloodFill {
    /// The drawing is read at up to this many pixels per point. Higher gives
    /// smoother edges and a bigger mask.
    static let maxPixelsPerPoint: CGFloat = 2
    /// The most pixels read along one side, so a big iPad canvas costs about
    /// what a phone does.
    static let maxPixelsPerSide: CGFloat = 1_000
    /// How far a pixel's color may be from the tapped pixel's and still fill,
    /// per channel out of 255. Lets the fill take in the soft edge of a line.
    static let tolerance = 96
    /// The fill grows this many pixels past the area, under the rest of the
    /// line's soft edge, so no light seam shows between the fill and the line.
    static let growPixels = 1

    /// Pixel states while filling.
    private static let blocked: UInt8 = 0
    private static let open: UInt8 = 1
    private static let filled: UInt8 = 2
    private static let edge: UInt8 = 3

    /// A stroke that fills the area around `point` on a square canvas of `side`
    /// points, or nil when the point is off the canvas.
    static func fillStroke(in drawing: PKDrawing, side: CGFloat, at point: CGPoint, color: UIColor) -> PKStroke? {
        guard side > 0 else {
            return nil
        }
        let scale = min(maxPixelsPerPoint, maxPixelsPerSide / side)
        let size = Int((side * scale).rounded())
        let seedX = Int(point.x * scale)
        let seedY = Int(point.y * scale)
        guard size > 0, (0..<size).contains(seedX), (0..<size).contains(seedY),
              let pixels = renderPixels(of: drawing, side: side, scale: scale, size: size)
        else {
            return nil
        }
        let area = fillArea(pixels: pixels, size: size, seed: seedY * size + seedX)
        guard let mask = maskPath(area: area, size: size, scale: scale) else {
            return nil
        }
        return stroke(covering: mask.bounds, mask: mask, color: color)
    }

    // MARK: Pixels

    /// The drawing as premultiplied RGBA, top row first.
    private static func renderPixels(of drawing: PKDrawing, side: CGFloat, scale: CGFloat, size: Int) -> [UInt32]? {
        var image: UIImage?
        // The canvas draws in light mode, so its ink colors are the light ones.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: scale)
        }
        var pixels = [UInt32](repeating: 0, count: size * size)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress,
                      width: size,
                      height: size,
                      bitsPerComponent: 8,
                      bytesPerRow: size * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }
            if let cgImage = image?.cgImage {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
            return true
        }
        return drawn ? pixels : nil
    }

    /// Every pixel connected to `seed` whose color is close to the seed's, then
    /// grown by `growPixels`. Filled pixels hold `filled`.
    static func fillArea(pixels: [UInt32], size: Int, seed: Int) -> [UInt8] {
        var area = [UInt8](repeating: blocked, count: pixels.count)
        pixels.withUnsafeBufferPointer { pixels in
            area.withUnsafeMutableBufferPointer { area in
                guard let pixels = pixels.baseAddress, let area = area.baseAddress else {
                    return
                }
                markOpen(area, pixels: pixels, count: size * size, target: pixels[seed])
                flood(area, size: size, seed: seed)
                for _ in 0..<growPixels {
                    grow(area, size: size)
                }
            }
        }
        return area
    }

    /// Marks the pixels whose color is within `tolerance` of `target`.
    private static func markOpen(
        _ area: UnsafeMutablePointer<UInt8>,
        pixels: UnsafePointer<UInt32>,
        count: Int,
        target: UInt32
    ) {
        let targetChannels = [0, 8, 16, 24].map { Int((target >> UInt32($0)) & 0xFF) }
        let (red, green, blue, alpha) = (targetChannels[0], targetChannels[1], targetChannels[2], targetChannels[3])
        var index = 0
        while index < count {
            let pixel = pixels[index]
            if pixel == target
                || (abs(Int(pixel & 0xFF) - red) <= tolerance
                    && abs(Int((pixel >> 8) & 0xFF) - green) <= tolerance
                    && abs(Int((pixel >> 16) & 0xFF) - blue) <= tolerance
                    && abs(Int(pixel >> 24) - alpha) <= tolerance) {
                area[index] = open
            }
            index += 1
        }
    }

    /// Scanline flood fill: fills the open run of a row, then queues the open
    /// runs touching it in the rows above and below.
    private static func flood(_ area: UnsafeMutablePointer<UInt8>, size: Int, seed: Int) {
        let count = size * size
        var stack = [seed]
        while let start = stack.popLast() {
            guard area[start] == open else {
                continue
            }
            let rowStart = start - start % size
            var left = start
            var right = start
            while left > rowStart, area[left - 1] == open {
                left -= 1
            }
            while right < rowStart + size - 1, area[right + 1] == open {
                right += 1
            }
            var index = left
            while index <= right {
                area[index] = filled
                index += 1
            }
            if rowStart > 0 {
                queueOpenRuns(area, from: left - size, through: right - size, into: &stack)
            }
            if rowStart + size < count {
                queueOpenRuns(area, from: left + size, through: right + size, into: &stack)
            }
        }
    }

    private static func queueOpenRuns(
        _ area: UnsafeMutablePointer<UInt8>,
        from first: Int,
        through last: Int,
        into stack: inout [Int]
    ) {
        var index = first
        while index <= last {
            if area[index] == open {
                stack.append(index)
                while index <= last, area[index] == open {
                    index += 1
                }
            }
            index += 1
        }
    }

    /// Grows the filled area by one pixel up, down, left, and right. The new
    /// pixels are marked `edge` first, so they do not spread within this pass.
    private static func grow(_ area: UnsafeMutablePointer<UInt8>, size: Int) {
        let count = size * size
        var index = 0
        while index < count {
            let column = index % size
            if area[index] != filled,
               (column > 0 && area[index - 1] == filled)
               || (column < size - 1 && area[index + 1] == filled)
               || (index >= size && area[index - size] == filled)
               || (index + size < count && area[index + size] == filled) {
                area[index] = edge
            }
            index += 1
        }
        index = 0
        while index < count {
            if area[index] == edge {
                area[index] = filled
            }
            index += 1
        }
    }

    // MARK: Stroke

    /// A rectangle of filled pixels: the run `start..<end` on the rows from
    /// `top` down to `bottom`, which stays 0 while the rectangle still grows.
    private struct OpenRect {
        var start: Int
        var end: Int
        var top: Int
        var bottom = 0
    }

    /// The filled area as rectangles in points: one per run of pixels in a
    /// row, with a run that repeats on the rows below merged into one taller
    /// rectangle.
    static func maskPath(area: [UInt8], size: Int, scale: CGFloat) -> UIBezierPath? {
        var closed: [OpenRect] = []
        var openRects: [OpenRect] = []
        area.withUnsafeBufferPointer { area in
            for row in 0...size {
                openRects = continueRects(openRects, onRow: row, area: area, size: size, closing: &closed)
            }
        }
        guard !closed.isEmpty else {
            return nil
        }
        let path = CGMutablePath()
        // PencilKit softens each rectangle's edges on its own, so two that only
        // touch leave a faint line between them. Each one reaches half a pixel
        // over and under, so the rectangles above and below overlap it.
        let overlap: CGFloat = 0.5
        for rect in closed {
            path.addRect(CGRect(
                x: CGFloat(rect.start) / scale,
                y: (CGFloat(rect.top) - overlap) / scale,
                width: CGFloat(rect.end - rect.start) / scale,
                height: (CGFloat(rect.bottom - rect.top) + 2 * overlap) / scale
            ))
        }
        return UIBezierPath(cgPath: path)
    }

    /// The rectangles open after `row`. A rectangle that no run on this row
    /// continues moves to `closed`. Both lists run left to right. The row past
    /// the last one has no runs, so it closes every rectangle.
    private static func continueRects(
        _ openRects: [OpenRect],
        onRow row: Int,
        area: UnsafeBufferPointer<UInt8>,
        size: Int,
        closing closed: inout [OpenRect]
    ) -> [OpenRect] {
        var nextRects: [OpenRect] = []
        var openIndex = 0
        var column = 0
        func closeOpenRect() {
            var rect = openRects[openIndex]
            rect.bottom = row
            closed.append(rect)
            openIndex += 1
        }
        while row < size, column < size {
            guard area[row * size + column] == filled else {
                column += 1
                continue
            }
            let start = column
            while column < size, area[row * size + column] == filled {
                column += 1
            }
            while openIndex < openRects.count,
                  openRects[openIndex].start < start
                  || (openRects[openIndex].start == start && openRects[openIndex].end < column) {
                closeOpenRect()
            }
            if openIndex < openRects.count, openRects[openIndex].start == start, openRects[openIndex].end == column {
                nextRects.append(openRects[openIndex])
                openIndex += 1
            } else {
                nextRects.append(OpenRect(start: start, end: column, top: row))
            }
        }
        while openIndex < openRects.count {
            closeOpenRect()
        }
        return nextRects
    }

    /// A line whose width covers `bounds`, run across its middle, clipped to `mask`.
    private static func stroke(covering bounds: CGRect, mask: UIBezierPath, color: UIColor) -> PKStroke {
        let width = max(bounds.width, bounds.height) + 2
        let points = [bounds.minX, bounds.maxX].map { x in
            PKStrokePoint(
                location: CGPoint(x: x, y: bounds.midY),
                timeOffset: 0,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.monoline, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: Date()),
            transform: .identity,
            mask: mask
        )
    }
}
