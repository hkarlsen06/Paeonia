// Builds the drawings for the App Store screenshots. The widget drawing of the
// first screenshot, one per locale, is a little plane on a looping dotted route
// that ends in a heart, with the days left until the seeded countdown ("Elena
// lands in Oslo") scribbled beside it. The Draw & Guess drawing has no words, so
// one file serves both locales: a smiling snail, the word Elena draws for
// Hjalmar to guess. Each is a real `PKDrawing.dataRepresentation()` payload made
// only of what the app's drawing screen makes: thick monoline pen strokes at
// widths the size slider allows, and bucket fills made the way
// `DrawingFloodFill` makes them, all in the palette inks.
//
//   swift scripts/app-store-drawing.swift scripts/assets/app-store
//
// Writes widget-drawing-plane-<locale>.pkdrawing and game-drawing-snail.pkdrawing,
// each with a -preview.png (rendered like `WidgetDrawingRasterizer`, over the
// widget's plum), and prints the inks and widths in each payload, the counts,
// and the bounds JSON the app sends with it.

import AppKit
import PencilKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("app-store-drawing: \(message)\n".utf8))
    exit(1)
}

func required<Value>(_ value: Value?, _ what: String) -> Value {
    guard let value else { fail("could not make \(what)") }
    return value
}

func say(_ line: String) {
    FileHandle.standardOutput.write(Data("\(line)\n".utf8))
}

// MARK: - App constants

/// `WidgetDrawingViewModel.fallbackCanvasSide`. Strokes live in this square.
let canvasSide: CGFloat = 320
let canvasRect = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)
/// `DrawingFloodFill` reads the canvas at up to 2 px per point and 1000 px per side.
let maskScale: CGFloat = min(2, 1_000 / canvasSide)
let maskSize = Int((canvasSide * maskScale).rounded())
/// `WidgetDrawingLimits`.
let maxPayloadBytes = 2_097_152
let maxStrokes = 5_000
let maxPoints = 200_000
/// `paeoniaWidgetBackground`.
let plum = NSColor(srgbRed: 0x38 / 255, green: 0x0F / 255, blue: 0x27 / 255, alpha: 1)

/// `WidgetDrawingColorChoice.palette`.
enum Ink: UInt32, CaseIterable {
    case blush = 0xFB_F3_F7
    case petal = 0xF2_7E_B2
    case pink = 0xEF_50_94
    case warm = 0xE8_5D_86
    case green = 0x5B_B9_8B
    case gold = 0xF2_B8_4B
    case blue = 0x6F_B1_F0
    case lavender = 0xB9_9C_F2

    var color: NSColor {
        NSColor(
            srgbRed: CGFloat((rawValue >> 16) & 0xFF) / 255,
            green: CGFloat((rawValue >> 8) & 0xFF) / 255,
            blue: CGFloat(rawValue & 0xFF) / 255,
            alpha: 1
        )
    }

    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let hex = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            .reduce(UInt32(0)) { $0 << 8 | UInt32(($1 * 255).rounded()) }
        self.init(rawValue: hex)
    }
}

// MARK: - Marks

/// A line drawn in one go with the pen: `PKInkingTool(.monoline, width:)`
/// with the size slider at `width`.
struct Trace {
    var points: [CGPoint]
    var ink: Ink
    var width: CGFloat
    var closed = false
}

/// A closed outline traced with the pen, then a paint-bucket tap inside it.
struct Shape {
    var outline: [CGPoint]
    var fill: Ink
    var line: Ink
    var width: CGFloat
}

/// One thing a person does on the canvas, in the order they do it.
enum Mark {
    case trace(Trace)
    case shape(Shape)
    /// A paint-bucket tap at a point, filling the area the strokes so far enclose.
    case bucket(CGPoint, Ink)
}

// MARK: - Geometry

func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
func * (lhs: CGPoint, scale: CGFloat) -> CGPoint { CGPoint(x: lhs.x * scale, y: lhs.y * scale) }

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

extension CGPoint {
    var length: CGFloat { (x * x + y * y).squareRoot() }

    func rotated(_ angle: CGFloat) -> CGPoint {
        CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }
}

func polar(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
    CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
}

func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

/// A Catmull-Rom curve through `points`.
func smooth(_ points: [CGPoint], closed: Bool, steps: Int = 10) -> [CGPoint] {
    guard points.count > 2 else { return points }
    let count = points.count
    func at(_ index: Int) -> CGPoint {
        closed ? points[(index % count + count) % count] : points[min(max(index, 0), count - 1)]
    }
    var result: [CGPoint] = []
    for segment in 0..<(closed ? count : count - 1) {
        let p0 = at(segment - 1), p1 = at(segment), p2 = at(segment + 1), p3 = at(segment + 2)
        for step in 0..<steps {
            let time = CGFloat(step) / CGFloat(steps)
            let constant = p1 * 2
            let linear = (p2 - p0) * time
            let square = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * (time * time)
            let cube = (p1 * 3 - p0 - p2 * 3 + p3) * (time * time * time)
            result.append((constant + linear + square + cube) * 0.5)
        }
    }
    if !closed { result.append(points[count - 1]) }
    return result
}

/// Points spaced `spacing` apart along the polyline.
func resample(_ points: [CGPoint], spacing: CGFloat, closed: Bool) -> [CGPoint] {
    guard let first = points.first, points.count > 1 else { return points }
    let path = closed ? points + [first] : points
    var result = [first]
    var carried: CGFloat = 0
    for index in 1..<path.count {
        let start = path[index - 1], end = path[index]
        let segment = (end - start).length
        guard segment > 0 else { continue }
        var distance = spacing - carried
        while distance <= segment {
            result.append(start + (end - start) * (distance / segment))
            distance += spacing
        }
        carried = segment - (distance - spacing)
    }
    if let end = path.last, let reached = result.last, (reached - end).length > spacing * 0.3 {
        result.append(end)
    }
    return result
}

/// A deterministic random source, so every run draws the same strokes.
struct Seeded {
    var state: UInt64

    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return CGFloat(mixed >> 11) / CGFloat(1 << 53)
    }

    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * next() }

    mutating func shake(_ amount: CGFloat) -> CGPoint { pt(range(-amount, amount), range(-amount, amount)) }
}

/// A slow, small sideways drift, like a hand that does not hold perfectly still.
func wobble(_ points: [CGPoint], amount: CGFloat, seed: UInt64) -> [CGPoint] {
    guard points.count > 2 else { return points }
    var random = Seeded(state: seed)
    let phase1 = random.range(0, 2 * .pi), phase2 = random.range(0, 2 * .pi)
    let wave1 = random.range(18, 30), wave2 = random.range(7, 11)
    var travelled: CGFloat = 0
    return points.enumerated().map { index, point in
        if index > 0 { travelled += (point - points[index - 1]).length }
        let tangent = points[min(points.count - 1, index + 1)] - points[max(0, index - 1)]
        let length = max(1e-6, tangent.length)
        let normal = CGPoint(x: -tangent.y / length, y: tangent.x / length)
        let drift = 0.7 * sin(travelled / wave1 + phase1) + 0.3 * sin(travelled / wave2 + phase2)
        return point + normal * (amount * drift)
    }
}

// MARK: - Strokes

/// Finger strokes on a 120 Hz screen land a point about every 1.6 pt.
let pointSpacing: CGFloat = 1.6
let creationDate = Date(timeIntervalSinceReferenceDate: 813_000_000)

struct StrokeBuilder {
    private(set) var strokes: [PKStroke] = []
    private var clock: TimeInterval = 0

    mutating func add(_ mark: Mark) {
        switch mark {
        case let .trace(trace):
            strokes.append(penStroke(trace))
        case let .shape(shape):
            let outline = penStroke(Trace(points: shape.outline, ink: shape.line, width: shape.width, closed: true))
            strokes.append(outline)
            // A shape the traced line already covers needs no tap.
            if let seed = seedPoint(outer: shape.outline, holes: [], lineWidth: shape.width * 2),
               let mask = maskPath(bucketArea(outlines: [outline], seed: seed)) {
                strokes.append(fillStroke(mask: mask, ink: shape.fill))
            }
        case let .bucket(point, ink):
            let seed = Int(point.y * maskScale) * maskSize + Int(point.x * maskScale)
            let mask = required(maskPath(bucketArea(outlines: strokes, seed: seed)), "a fill")
            strokes.append(fillStroke(mask: mask, ink: ink))
        }
    }

    private mutating func penStroke(_ trace: Trace) -> PKStroke {
        precondition((1...12).contains(trace.width), "pen width \(trace.width) is outside the slider's 1...12")
        let wobbled = wobble(trace.points, amount: 0.4, seed: UInt64(strokes.count + 1))
        var line = resample(wobbled, spacing: pointSpacing, closed: trace.closed)
        if trace.closed { line += Array(line.prefix(3)) }
        // Monoline draws a point of size s as a line 2s - 4 wide, and the app's
        // pen draws a line 2w wide for width w.
        let points = line.enumerated().map { index, location in
            strokePoint(location, timeOffset: Double(index) / 120, size: trace.width + 2)
        }
        defer { clock += Double(points.count) / 120 + 0.35 }
        return makeStroke(ink: PKInk(.monoline, color: trace.ink.color), points: points, mask: nil)
    }

    /// `DrawingFloodFill.stroke(covering:mask:color:)`: one wide monoline line
    /// across the area's bounds, clipped to the mask.
    private mutating func fillStroke(mask: NSBezierPath, ink: Ink) -> PKStroke {
        let bounds = mask.bounds
        let size = max(bounds.width, bounds.height) + 2
        let points = [bounds.minX, bounds.maxX].map { x in
            strokePoint(CGPoint(x: x, y: bounds.midY), timeOffset: 0, size: size)
        }
        defer { clock += 0.6 }
        return makeStroke(ink: PKInk(.monoline, color: ink.color), points: points, mask: mask)
    }

    private func strokePoint(_ location: CGPoint, timeOffset: TimeInterval, size: CGFloat) -> PKStrokePoint {
        PKStrokePoint(
            location: location,
            timeOffset: timeOffset,
            size: CGSize(width: size, height: size),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )
    }

    private func makeStroke(ink: PKInk, points: [PKStrokePoint], mask: NSBezierPath?) -> PKStroke {
        let index = strokes.count
        return PKStroke(
            ink: ink,
            path: PKStrokePath(controlPoints: points, creationDate: creationDate.addingTimeInterval(clock)),
            transform: .identity,
            mask: mask,
            randomSeed: UInt32(truncatingIfNeeded: 0x5EED_0000 &+ index &* 2_654_435_761),
            id: required(UUID(uuidString: String(format: "9E0A1A00-0000-4000-8000-%012X", index + 1)), "a stroke id"),
            renderGroupID: nil,
            renderState: nil
        )
    }
}

// MARK: - Paint bucket

private let blocked: UInt8 = 0
private let open: UInt8 = 1
private let filled: UInt8 = 2
private let edge: UInt8 = 3

func bitmap(_ data: UnsafeMutableRawPointer?, side: Int, gray: Bool) -> CGContext {
    required(
        CGContext(
            data: data,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: gray ? side : side * 4,
            space: gray ? CGColorSpaceCreateDeviceGray() : required(CGColorSpace(name: CGColorSpace.sRGB), "sRGB"),
            bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        "a bitmap"
    )
}

/// Where the person taps: the inside pixel nearest the shape's middle, as far
/// from the traced line as the shape allows. Nil when the line covers it all.
func seedPoint(outer: [CGPoint], holes: [[CGPoint]], lineWidth: CGFloat) -> Int? {
    for margin: CGFloat in [3, 1.5, 0.5] {
        if let seed = seedPoint(outer: outer, holes: holes, clearance: lineWidth + margin) {
            return seed
        }
    }
    return nil
}

func seedPoint(outer: [CGPoint], holes: [[CGPoint]], clearance: CGFloat) -> Int? {
    var pixels = [UInt8](repeating: 0, count: maskSize * maskSize)
    pixels.withUnsafeMutableBytes { buffer in
        let context = bitmap(buffer.baseAddress, side: maskSize, gray: true)
        context.setShouldAntialias(false)
        context.translateBy(x: 0, y: CGFloat(maskSize))
        context.scaleBy(x: maskScale, y: -maskScale)
        let path = CGMutablePath()
        for ring in [outer] + holes {
            path.addLines(between: ring)
            path.closeSubpath()
        }
        context.addPath(path)
        context.setFillColor(gray: 1, alpha: 1)
        context.fillPath(using: .evenOdd)
        context.addPath(path)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(clearance)
        context.strokePath()
    }
    let middle = outer.reduce(CGPoint.zero, +) * (1 / CGFloat(outer.count)) * maskScale
    func distance(_ index: Int) -> CGFloat {
        (CGPoint(x: index % maskSize, y: index / maskSize) - middle).length
    }
    return pixels.indices.filter { pixels[$0] > 127 }.min { distance($0) < distance($1) }
}

/// `DrawingFloodFill.renderPixels` for the shape's traced outlines: premultiplied
/// RGBA, top row first, in light appearance.
func outlinePixels(_ outlines: [PKStroke]) -> [UInt32] {
    var image: NSImage?
    required(NSAppearance(named: .aqua), "the light appearance").performAsCurrentDrawingAppearance {
        image = PKDrawing(strokes: outlines).image(from: canvasRect, scale: maskScale)
    }
    let outline = required(image?.cgImage(forProposedRect: nil, context: nil, hints: nil), "the outline image")
    var pixels = [UInt32](repeating: 0, count: maskSize * maskSize)
    pixels.withUnsafeMutableBytes { buffer in
        bitmap(buffer.baseAddress, side: maskSize, gray: false)
            .draw(outline, in: CGRect(x: 0, y: 0, width: maskSize, height: maskSize))
    }
    return pixels
}

/// `DrawingFloodFill.fillArea`: every pixel connected to `seed` whose color is
/// within `tolerance` of the seed's, grown by one pixel.
func bucketArea(outlines: [PKStroke], seed: Int) -> [UInt8] {
    let pixels = outlinePixels(outlines)
    let tolerance = 96
    func channel(_ pixel: UInt32, _ shift: UInt32) -> Int { Int((pixel >> shift) & 0xFF) }
    let target = pixels[seed]
    precondition(channel(target, 24) <= tolerance, "the tap landed on the traced line")
    var area = pixels.map { pixel -> UInt8 in
        let near = [UInt32(0), 8, 16, 24].allSatisfy { abs(channel(pixel, $0) - channel(target, $0)) <= tolerance }
        return near ? open : blocked
    }
    flood(&area, from: seed)
    let border = (0..<maskSize).flatMap { index in
        [index, maskSize * (maskSize - 1) + index, index * maskSize, index * maskSize + maskSize - 1]
    }
    precondition(border.allSatisfy { area[$0] != filled }, "the bucket leaked out of an outline")
    grow(&area)
    return area
}

/// `DrawingFloodFill.flood`: fills the open run of a row, then queues the open
/// runs touching it in the rows above and below.
func flood(_ area: inout [UInt8], from seed: Int) {
    var stack = [seed]
    while let start = stack.popLast() {
        guard area[start] == open else { continue }
        let rowStart = start - start % maskSize
        var left = start, right = start
        while left > rowStart, area[left - 1] == open { left -= 1 }
        while right < rowStart + maskSize - 1, area[right + 1] == open { right += 1 }
        for index in left...right { area[index] = filled }
        for shift in [-maskSize, maskSize] where (0..<maskSize * maskSize).contains(rowStart + shift) {
            queueOpenRuns(area, from: left + shift, through: right + shift, into: &stack)
        }
    }
}

/// `DrawingFloodFill.queueOpenRuns`.
func queueOpenRuns(_ area: [UInt8], from first: Int, through last: Int, into stack: inout [Int]) {
    var index = first
    while index <= last {
        if area[index] == open {
            stack.append(index)
            while index <= last, area[index] == open { index += 1 }
        }
        index += 1
    }
}

/// `DrawingFloodFill.grow`: one pixel up, down, left, and right.
func grow(_ area: inout [UInt8]) {
    let count = maskSize * maskSize
    for index in 0..<count where area[index] != filled {
        let column = index % maskSize
        if (column > 0 && area[index - 1] == filled)
            || (column < maskSize - 1 && area[index + 1] == filled)
            || (index >= maskSize && area[index - maskSize] == filled)
            || (index + maskSize < count && area[index + maskSize] == filled) {
            area[index] = edge
        }
    }
    for index in 0..<count where area[index] == edge { area[index] = filled }
}

/// A rectangle of filled pixels: the run `start..<end` on the rows from `top`
/// down to `bottom`.
struct Run {
    var start: Int
    var end: Int
    var top: Int
    var bottom = 0
}

/// The runs of filled pixels on `row`, left to right. The row past the last
/// one has none.
func rowRuns(_ row: Int, area: [UInt8]) -> [Run] {
    guard row < maskSize else { return [] }
    var runs: [Run] = []
    var column = 0
    while column < maskSize {
        guard area[row * maskSize + column] == filled else {
            column += 1
            continue
        }
        let start = column
        while column < maskSize, area[row * maskSize + column] == filled { column += 1 }
        runs.append(Run(start: start, end: column, top: row))
    }
    return runs
}

/// `DrawingFloodFill.continueRects`: the runs open after `row`. A run that no
/// run on this row continues moves to `closed`.
func continueRuns(_ openRuns: [Run], onRow row: Int, area: [UInt8], closing closed: inout [Run]) -> [Run] {
    var next: [Run] = []
    var openIndex = 0
    func closeOpenRun() {
        var run = openRuns[openIndex]
        run.bottom = row
        closed.append(run)
        openIndex += 1
    }
    for run in rowRuns(row, area: area) {
        while openIndex < openRuns.count,
              openRuns[openIndex].start < run.start
              || (openRuns[openIndex].start == run.start && openRuns[openIndex].end < run.end) {
            closeOpenRun()
        }
        if openIndex < openRuns.count, openRuns[openIndex].start == run.start, openRuns[openIndex].end == run.end {
            next.append(openRuns[openIndex])
            openIndex += 1
        } else {
            next.append(run)
        }
    }
    while openIndex < openRuns.count { closeOpenRun() }
    return next
}

/// `DrawingFloodFill.maskPath`: one rectangle per run of filled pixels, merged
/// down the rows while the run repeats, each reaching half a pixel over and
/// under so neighbors overlap.
func maskPath(_ area: [UInt8]) -> NSBezierPath? {
    var closed: [Run] = []
    var openRuns: [Run] = []
    for row in 0...maskSize {
        openRuns = continueRuns(openRuns, onRow: row, area: area, closing: &closed)
    }
    guard !closed.isEmpty else { return nil }
    let path = NSBezierPath()
    for run in closed {
        path.appendRect(CGRect(
            x: CGFloat(run.start) / maskScale,
            y: (CGFloat(run.top) - 0.5) / maskScale,
            width: CGFloat(run.end - run.start) / maskScale,
            height: (CGFloat(run.bottom - run.top) + 1) / maskScale
        ))
    }
    return path
}

// MARK: - Rendering

/// `WidgetDrawingRasterizer`: light appearance, transparent background.
func render(_ drawing: PKDrawing, pixelWidth: CGFloat) -> CGImage {
    var image: NSImage?
    required(NSAppearance(named: .aqua), "the light appearance").performAsCurrentDrawingAppearance {
        image = drawing.image(from: canvasRect, scale: max(1, pixelWidth / canvasSide))
    }
    return required(image?.cgImage(forProposedRect: nil, context: nil, hints: nil), "the drawing image")
}

/// The raster over the widget's plum, clipped like `DrawingCanvasShape`.
func onPlum(_ drawing: CGImage, side: Int) -> CGImage {
    let context = bitmap(nil, side: side, gray: false)
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    context.setFillColor(plum.cgColor)
    context.fill(rect)
    let radius = CGFloat(side) * 28 / 360
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(drawing, in: rect)
    return required(context.makeImage(), "the preview")
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = required(
        CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil),
        url.path
    )
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "could not write \(url.path)")
}

// MARK: - Handwriting

/// A character as a finger writes it on a phone, in x-height units with the
/// baseline at 0 and up negative. Each stroke is one touch. A point listed
/// twice in a row is a sharp turn, where the finger changes direction without
/// lifting.
struct Glyph {
    var advance: CGFloat
    var strokes: [[CGPoint]]
}

let bowl = [
    pt(0.72, -0.82), pt(0.5, -1.0), pt(0.18, -0.9), pt(0.02, -0.5), pt(0.12, -0.08), pt(0.4, 0.0), pt(0.65, -0.22),
]
let stem = [pt(0.0, -1.0), pt(0.0, -0.5), pt(0.01, 0.0), pt(0.01, 0.0)]

let glyphs: [Character: Glyph] = [
    "1": Glyph(advance: 0.3, strokes: [
        [pt(-0.05, -1.22), pt(0.12, -1.4), pt(0.22, -1.58), pt(0.22, -1.58), pt(0.21, -0.8), pt(0.2, 0)],
    ]),
    "2": Glyph(advance: 0.8, strokes: [[
        pt(0.02, -1.2), pt(0.18, -1.5), pt(0.48, -1.6), pt(0.72, -1.4), pt(0.7, -1.05), pt(0.45, -0.6),
        pt(0.02, 0.0), pt(0.02, 0.0), pt(0.4, 0.02), pt(0.8, -0.02),
    ]]),
    "!": Glyph(advance: 0.08, strokes: [
        [pt(0.06, -1.58), pt(0.04, -0.95), pt(0.02, -0.42)],
        [pt(0.0, -0.08), pt(0.02, -0.05)],
    ]),
    "a": Glyph(advance: 0.82, strokes: [
        bowl + [pt(0.75, -0.65), pt(0.77, -1.0), pt(0.77, -1.0), pt(0.77, -0.45), pt(0.82, 0)],
    ]),
    "d": Glyph(advance: 0.83, strokes: [
        bowl + [pt(0.76, -0.7), pt(0.79, -1.2), pt(0.8, -1.65), pt(0.8, -1.65), pt(0.8, -0.8), pt(0.83, 0)],
    ]),
    "e": Glyph(advance: 0.74, strokes: [[
        pt(0.04, -0.5), pt(0.4, -0.52), pt(0.72, -0.6), pt(0.66, -0.88), pt(0.4, -1.0),
        pt(0.12, -0.88), pt(0.0, -0.5), pt(0.12, -0.1), pt(0.42, 0.0), pt(0.72, -0.14),
    ]]),
    "g": Glyph(advance: 0.8, strokes: [bowl + [
        pt(0.75, -0.65), pt(0.77, -1.0), pt(0.77, -1.0), pt(0.78, -0.2), pt(0.72, 0.35),
        pt(0.5, 0.65), pt(0.22, 0.68), pt(0.02, 0.5),
    ]]),
    "r": Glyph(advance: 0.55, strokes: [stem + [pt(0.03, -0.55), pt(0.17, -0.88), pt(0.38, -1.0), pt(0.58, -0.95)]]),
    "s": Glyph(advance: 0.7, strokes: [[
        pt(0.68, -0.88), pt(0.45, -1.0), pt(0.15, -0.93), pt(0.06, -0.72), pt(0.25, -0.55),
        pt(0.55, -0.43), pt(0.7, -0.22), pt(0.55, -0.02), pt(0.25, 0.0), pt(0.0, -0.12),
    ]]),
    "y": Glyph(advance: 0.8, strokes: [
        [pt(0.0, -1.0), pt(0.18, -0.5), pt(0.4, -0.02)],
        [pt(0.8, -1.0), pt(0.55, -0.35), pt(0.32, 0.25), pt(0.18, 0.7)],
    ]),
]

/// How far a finger strays from the stroke it means to draw, as a share of the
/// letter's x-height.
let shakiness: CGFloat = 0.05
/// The space between letters, as a share of the x-height.
let letterGap: CGFloat = 0.4
/// The app's pen keeps one width per slider setting. This much variation per
/// stroke stands in for the slightly different marks a finger leaves. Set it
/// to 0 for strokes that all share one slider width.
let widthVariation: CGFloat = 0.25

/// The pen as the drawing screen sets it: a palette ink and the size slider.
struct Pen {
    var ink: Ink
    var width: CGFloat
}

/// `points` as one touch: each point moved a little by the shaking hand, and
/// the stretches between sharp turns drawn as smooth curves.
func handDrawn(_ points: [CGPoint], shake: CGFloat, random: inout Seeded) -> [CGPoint] {
    var segments: [[CGPoint]] = [[]]
    for point in points {
        if segments[segments.count - 1].last == point {
            segments.append([point])
        } else {
            segments[segments.count - 1].append(point)
        }
    }
    var result: [CGPoint] = []
    for segment in segments {
        var moved = segment.map { $0 + random.shake(shake) }
        if let joint = result.last { moved[0] = joint }
        let curve = smooth(moved, closed: false, steps: 8)
        result += result.isEmpty ? curve : Array(curve.dropFirst())
    }
    return result
}

func handWidth(_ pen: Pen, _ random: inout Seeded) -> CGFloat {
    pen.width + random.range(-widthVariation, widthVariation)
}

/// One touch of `pen` along `points`, drawn by a shaking hand.
func touch(_ points: [CGPoint], _ pen: Pen, shake: CGFloat, random: inout Seeded) -> Mark {
    let line = handDrawn(points, shake: shake, random: &random)
    return .trace(Trace(points: line, ink: pen.ink, width: handWidth(pen, &random)))
}

/// A closed outline drawn by a shaking hand, then filled with the bucket.
func filled(_ points: [CGPoint], _ pen: Pen, shake: CGFloat, random: inout Seeded) -> Mark {
    let outline = handDrawn(points, shake: shake, random: &random)
    return .shape(Shape(outline: outline, fill: pen.ink, line: pen.ink, width: handWidth(pen, &random)))
}

/// The letters of `line` as pen strokes, with its baseline starting at
/// `origin`. Each letter sits a little differently: size, tilt, and height.
func write(_ line: String, at origin: CGPoint, xHeight: CGFloat, pen: Pen, random: inout Seeded) -> [Mark] {
    var marks: [Mark] = []
    var x = origin.x
    for character in line {
        guard let glyph = glyphs[character] else {
            x += 0.6 * xHeight
            continue
        }
        let scale = xHeight * random.range(0.9, 1.1)
        let tilt = random.range(-0.1, 0.1)
        let slant = 0.06 + random.range(-0.05, 0.05)
        let base = pt(x, origin.y + random.range(-0.08, 0.08) * xHeight)
        for stroke in glyph.strokes {
            let placed = stroke.map { base + pt($0.x + -$0.y * slant, $0.y).rotated(tilt) * scale }
            marks.append(touch(placed, pen, shake: shakiness * xHeight, random: &random))
        }
        x += (glyph.advance + letterGap + random.range(-0.07, 0.07)) * xHeight
    }
    return marks
}

extension Mark {
    var points: [CGPoint] {
        switch self {
        case let .trace(trace): trace.points
        case let .shape(shape): shape.outline
        case let .bucket(point, _): [point]
        }
    }

    func mapped(_ transform: (CGPoint) -> CGPoint) -> Mark {
        switch self {
        case var .trace(trace):
            trace.points = trace.points.map(transform)
            return .trace(trace)
        case var .shape(shape):
            shape.outline = shape.outline.map(transform)
            return .shape(shape)
        case let .bucket(point, ink):
            return .bucket(transform(point), ink)
        }
    }
}

/// The seeded countdown, "Elena lands in Oslo", is this many days away.
let daysToGo = "12"

/// The days left, scribbled as a big number over a smaller word, centered on
/// `center` and tilted up a little.
func daysLeft(_ word: String, center: CGPoint, pen: Pen, random: inout Seeded) -> [Mark] {
    var marks = write(daysToGo, at: pt(0, 0), xHeight: 27, pen: pen, random: &random)
    marks += write(word, at: pt(12, 37), xHeight: 19, pen: pen, random: &random)
    let points = marks.flatMap(\.points)
    let xs = points.map(\.x), ys = points.map(\.y)
    let middle = pt(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
    return marks.map { $0.mapped { center + ($0 - middle).rotated(degrees(-8)) } }
}

// MARK: - The plane, the route, and the heart

/// A little plane seen from the side, nose along +x and `length` long: a
/// blush body, a gold tail fin and wing, and three dabs of pink for windows.
func plane(at center: CGPoint, length: CGFloat, heading: CGFloat, random: inout Seeded) -> [Mark] {
    func local(_ points: [CGPoint]) -> [CGPoint] { points.map { center + ($0 * (length / 2)).rotated(heading) } }
    let shake = length * 0.012
    let body = Pen(ink: .blush, width: 3.0), trim = Pen(ink: .gold, width: 3.0)
    let fin = [pt(-0.6, -0.12), pt(-0.86, -0.62), pt(-0.86, -0.62), pt(-1.02, -0.6), pt(-1.02, -0.6), pt(-0.98, -0.06)]
    let hull = [
        pt(1.0, 0.04), pt(0.82, -0.2), pt(0.3, -0.29), pt(-0.45, -0.24), pt(-0.95, -0.1),
        pt(-0.96, 0.1), pt(-0.45, 0.25), pt(0.35, 0.28), pt(0.84, 0.2), pt(1.0, 0.04),
    ]
    let wing = [pt(0.28, 0.06), pt(-0.18, 0.66), pt(-0.18, 0.66), pt(-0.42, 0.66), pt(-0.42, 0.66), pt(-0.16, 0.06)]
    var marks = [
        filled(local(fin), trim, shake: shake, random: &random),
        filled(local(hull), body, shake: shake, random: &random),
        filled(local(wing), trim, shake: shake, random: &random),
    ]
    let windows = Pen(ink: .pink, width: 3.0)
    for x in [0.55, 0.3, 0.05] as [CGFloat] {
        marks.append(touch(local([pt(x, -0.06), pt(x + 0.03, -0.06)]), windows, shake: 0, random: &random))
    }
    return marks
}

/// A heart about 1.5 wide and 1.35 tall, started and ended at the dip on top.
let heartPoints = [
    pt(0.0, -0.55), pt(-0.22, -0.86), pt(-0.55, -0.86), pt(-0.74, -0.55), pt(-0.62, -0.18), pt(-0.32, 0.15),
    pt(0.02, 0.5), pt(0.02, 0.5), pt(0.3, 0.18), pt(0.62, -0.18), pt(0.76, -0.55), pt(0.58, -0.86),
    pt(0.24, -0.86), pt(0.0, -0.55),
]

/// The plane's route as one curve: in from the top left, a loose loop, then
/// down toward the heart.
let route = smooth([
    pt(30, 74), pt(68, 84), pt(104, 102), pt(138, 122), pt(160, 106), pt(154, 78), pt(130, 74),
    pt(120, 98), pt(134, 126), pt(162, 154), pt(192, 180), pt(222, 207), pt(244, 226), pt(256, 238),
], closed: false, steps: 12)

/// The route as quick dashes, the way a finger dots a line: each dash one
/// touch, with a gap where the plane sits.
func dashes(along path: [CGPoint], skipping plane: CGPoint, pen: Pen, random: inout Seeded) -> [Mark] {
    let points = resample(path, spacing: 1, closed: false)
    var marks: [Mark] = []
    var index = 0
    while index + 6 < points.count {
        let dash = Array(points[index...(index + 6)])
        if dash.allSatisfy({ ($0 - plane).length > 47 }) {
            marks.append(touch(dash, pen, shake: 0.6, random: &random))
        }
        index += 14 + Int(random.range(-1.5, 1.5))
    }
    return marks
}

// MARK: - The drawings

/// The word under the number of days, in each locale.
let countdowns: [(locale: String, word: String)] = [
    ("en", "days!"),
    ("nb", "dager!"),
]

/// The widget's own label and time sit over the bottom-left corner, so nothing
/// is drawn there.
let labelCorner = CGRect(x: 0, y: 205, width: 135, height: 115)

func drawing(word: String, seed: UInt64) -> [Mark] {
    var random = Seeded(state: 11)
    let planeCenter = pt(194, 182)
    var marks = dashes(along: route, skipping: planeCenter, pen: Pen(ink: .pink, width: 3.0), random: &random)
    let heart = heartPoints.map { pt(274, 258) + $0.rotated(0.15) * 29 }
    marks.append(filled(heart, Pen(ink: .pink, width: 3.4), shake: 1.2, random: &random))
    marks += plane(at: planeCenter, length: 86, heading: degrees(36), random: &random)
    var writing = Seeded(state: seed)
    marks += daysLeft(word, center: pt(234, 84), pen: Pen(ink: .gold, width: 3.5), random: &writing)
    return marks
}

// MARK: - The snail

/// The word Elena draws in the Draw & Guess screenshot.
let guessWord = "snail"

/// A smiling snail heading right, drawn the way a finger does it in about 20
/// seconds: a pink shell, a gold body traced from the shell and filled with one
/// bucket tap, a spiral, two eye stalks, a smile, a strip of grass and a heart.
func snail() -> [Mark] {
    var random = Seeded(state: 7)
    let shellCenter = pt(130, 150), shellRadius: CGFloat = 62
    let shell = (0...12).map { shellCenter + polar(degrees(CGFloat($0) * 30 - 90), shellRadius) }
    var marks = [filled(shell, Pen(ink: .pink, width: 3.5), shake: 2, random: &random)]

    let gold = Pen(ink: .gold, width: 3.5)
    // From the shell's lower left, along the ground, up and over the head, back into the shell.
    marks.append(touch([
        pt(87, 194), pt(76, 215), pt(90, 234), pt(150, 240), pt(225, 236), pt(262, 222), pt(276, 195),
        pt(272, 163), pt(255, 141), pt(234, 136), pt(215, 148), pt(205, 168), pt(182, 184),
    ], gold, shake: 1.5, random: &random))
    marks.append(.bucket(pt(240, 190), .gold))

    let spiral = (0...44).map { step -> CGPoint in
        let turn = CGFloat(step) / 44
        return shellCenter + pt(-2, 2) + polar(degrees(200 + 810 * turn), 4 + 40 * turn)
    }
    marks.append(touch(spiral, Pen(ink: .blush, width: 3), shake: 1, random: &random))

    for (base, tip) in [(pt(230, 140), pt(214, 94)), (pt(250, 142), pt(266, 98))] {
        marks.append(touch([base, (base + tip) * 0.5 + pt(-3, 0), tip], gold, shake: 1, random: &random))
        marks.append(touch([tip, tip + pt(1.5, 0.5)], Pen(ink: .gold, width: 7), shake: 0, random: &random))
    }
    marks.append(touch([pt(240, 172), pt(250, 180), pt(262, 174)], Pen(ink: .pink, width: 2.5), shake: 0.6,
                       random: &random))
    marks.append(touch([pt(266, 162), pt(267, 163)], Pen(ink: .petal, width: 5), shake: 0, random: &random))

    marks.append(touch([pt(36, 256), pt(90, 251), pt(150, 255), pt(210, 250), pt(286, 254)],
                       Pen(ink: .green, width: 3), shake: 1.5, random: &random))
    let heart = heartPoints.map { pt(282, 70) + $0.rotated(0.2) * 26 }
    marks.append(filled(heart, Pen(ink: .petal, width: 3), shake: 0.8, random: &random))
    return marks
}

// MARK: - Main

/// PencilKit keeps per-app state in preferences and crashes in a process with
/// no bundle identifier, which the `swift` interpreter and a plain `swiftc`
/// build both are. So the script builds itself with one and runs that build.
func runWithBundleIdentifier() throws -> Never {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("app-store-drawing-\(getpid())")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let plist = work.appendingPathComponent("Info.plist")
    let info = ["CFBundleIdentifier": "no.paeonia.app-store-drawing"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
    let binary = work.appendingPathComponent("app-store-drawing")
    func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
    var status = try run("/usr/bin/xcrun", [
        "swiftc", "-O", #filePath, "-o", binary.path,
        "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", plist.path,
    ])
    if status == 0 {
        status = try run(binary.path, Array(CommandLine.arguments.dropFirst()))
    }
    try? FileManager.default.removeItem(at: work)
    exit(status)
}

/// What the payload holds, tool by tool: the bucket's masked strokes and the
/// pen at its slider width.
func describeInks(_ drawing: PKDrawing) {
    var widths: [String: Set<CGFloat>] = [:]
    for stroke in drawing.strokes {
        guard let ink = Ink(stroke.ink.color) else { fail("an ink outside the palette") }
        if stroke.mask != nil {
            widths["  bucket \(ink)", default: []] = []
        } else {
            let size = stroke.path.first.map { $0.size.width } ?? 0
            widths["  pen \(ink)", default: []].insert(((size - 2) * 100).rounded() / 100)
        }
    }
    for (key, values) in widths.sorted(by: { $0.key < $1.key }) {
        let listed = values.sorted().map { String(format: "%g", $0) }.joined(separator: ", ")
        say(listed.isEmpty ? key : "\(key) at \(listed)")
    }
}

/// Builds, checks, and writes one payload and its preview as `<name>.pkdrawing`
/// and `<name>-preview.png`. A widget drawing keeps out of `labelCorner`.
func publish(_ marks: [Mark], name: String, isWidget: Bool, to directory: URL) throws {
    var builder = StrokeBuilder()
    for mark in marks { builder.add(mark) }
    let built = PKDrawing(strokes: builder.strokes)
    let data = built.dataRepresentation()
    let drawing = try PKDrawing(data: data)
    let pointCount = drawing.strokes.reduce(0) { $0 + $1.path.count }
    precondition(drawing.strokes.count == builder.strokes.count, "decoding changed the stroke count")
    precondition(Set(drawing.strokes.map(\.id)).count == drawing.strokes.count, "two strokes share an id")
    // The encoder writes monoline strokes as version-1 pen ink, so compare what
    // the decoded payload draws instead of ink names.
    precondition(
        render(drawing, pixelWidth: 880).dataProvider?.data == render(built, pixelWidth: 880).dataProvider?.data,
        "the decoded payload draws differently"
    )
    precondition(
        data.count <= maxPayloadBytes && drawing.strokes.count <= maxStrokes && pointCount <= maxPoints,
        "past the server's limits"
    )
    precondition(
        !isWidget || drawing.strokes.allSatisfy { !$0.renderBounds.intersects(labelCorner) },
        "a stroke reaches into the corner under the widget's label"
    )
    try data.write(to: directory.appendingPathComponent("\(name).pkdrawing"))
    let preview = directory.appendingPathComponent("\(name)-preview.png")
    writePNG(onPlum(render(drawing, pixelWidth: 1_080), side: 1_080), to: preview)

    let bounds = drawing.bounds
    say("\(name): strokes \(drawing.strokes.count), points \(pointCount), bytes \(data.count)")
    say(String(
        format: #"  bounds {"x":%g,"y":%g,"width":%g,"height":%g,"canvasSide":%g}"#,
        bounds.minX, bounds.minY, bounds.width, bounds.height, canvasSide
    ))
    describeInks(drawing)
}

if Bundle.main.bundleIdentifier == nil {
    try runWithBundleIdentifier()
}
guard CommandLine.arguments.count == 2 else {
    fail("usage: swift scripts/app-store-drawing.swift <out-dir>")
}
let outDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
for (index, countdown) in countdowns.enumerated() {
    let marks = drawing(word: countdown.word, seed: UInt64(41 + index))
    try publish(marks, name: "widget-drawing-plane-\(countdown.locale)", isWidget: true, to: outDirectory)
}
try publish(snail(), name: "game-drawing-\(guessWord)", isWidget: false, to: outDirectory)
