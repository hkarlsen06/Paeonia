import PencilKit
import UIKit

/// One touch sample of a stroke, in the drawing's coordinates.
nonisolated struct InkSample: Equatable, Sendable {
    /// Canvas points. The y is negative in an overscan strip above the drawing.
    var location: CGPoint
    /// Seconds since the stroke began.
    var timeOffset: TimeInterval
    /// Apple Pencil pressure in PencilKit's scale. A finger has none.
    var force: CGFloat?
    var azimuth: CGFloat
    var altitude: CGFloat
}

/// A pen or pencil stroke being drawn, here or by the partner. The wet ink on
/// this phone, the partner's live preview and the finished stroke are all
/// `pencilKitStroke()` of one of these, so they look the same.
nonisolated struct InkStroke: Equatable, Sendable {
    /// The clean shape a held stroke turned into, and when.
    nonisolated struct Snap: Equatable, Codable, Sendable {
        var shape: SnappedShape
        /// Seconds since the stroke began.
        var time: TimeInterval
    }

    /// The shape as it snapped and where the finger was then. Dragging on
    /// resizes from these, so the shape never drifts from rounding.
    private nonisolated struct Grab: Equatable, Sendable {
        var shape: SnappedShape
        var finger: CGPoint
    }

    /// How far apart the points of a snapped outline are, in canvas points.
    private static let outlineSpacing: CGFloat = 3

    let style: InkStyle
    /// The pencil texture's seed. Fixed per stroke, so the texture holds still
    /// while the stroke grows and when it lands on the canvas.
    let seed: UInt32
    /// With the seed and the point count, this names the stroke on both phones
    /// (`WidgetLiveStrokeSync.key`).
    let creationDate: Date
    /// The touches, all of them, also after a snap.
    private(set) var samples: [InkSample]
    private(set) var snap: Snap?
    private var grab: Grab?

    init(
        style: InkStyle,
        first: InkSample,
        seed: UInt32 = .random(in: .min ... .max),
        creationDate: Date = Date()
    ) {
        self.style = style
        self.seed = seed
        self.creationDate = creationDate
        samples = [first]
    }

    mutating func append(_ newSamples: [InkSample]) {
        samples.append(contentsOf: newSamples)
    }

    mutating func snap(to shape: SnappedShape, at time: TimeInterval) {
        snap = Snap(shape: shape, time: time)
        grab = Grab(shape: shape, finger: samples[samples.count - 1].location)
    }

    mutating func unsnap() {
        snap = nil
        grab = nil
    }

    /// Resizes a snapped shape to follow the finger, the last touch, the way
    /// it moved since the snap (`SnappedShape.resized`).
    mutating func resizeSnapToFinger() {
        guard let grab else {
            return
        }
        snap?.shape = grab.shape.resized(grabbedAt: grab.finger, draggedTo: samples[samples.count - 1].location)
    }

    /// What the stroke is drawn through: the touches, or once snapped, the
    /// shape's outline. The outline takes the touches' middle pressure and
    /// tilt and spreads their time over its length.
    var drawnSamples: [InkSample] {
        guard let snap else {
            return samples
        }
        let outline = snap.shape.outline(spacing: Self.outlineSpacing)
        let forces = samples.compactMap(\.force)
        let force = forces.isEmpty ? nil : Self.median(forces)
        let azimuth = Self.median(samples.map(\.azimuth))
        let altitude = Self.median(samples.map(\.altitude))
        let step = snap.time / Double(max(outline.count - 1, 1))
        return outline.enumerated().map { index, location in
            InkSample(
                location: location,
                timeOffset: Double(index) * step,
                force: force,
                azimuth: azimuth,
                altitude: altitude
            )
        }
    }

    /// The stroke as far as it was drawn `elapsed` seconds in, or nil before
    /// its first sample.
    func prefix(through elapsed: TimeInterval) -> InkStroke? {
        let shown = samples.prefix { $0.timeOffset <= elapsed }
        guard !shown.isEmpty else {
            return nil
        }
        var stroke = self
        stroke.samples = Array(shown)
        if let snap, elapsed < snap.time {
            stroke.unsnap()
        }
        return stroke
    }

    /// The PencilKit stroke. `predicted` samples come only from the wet ink on
    /// this phone and never reach the finished stroke. `transform` scales a
    /// partner's stroke to this canvas, as `PKDrawing.scaled` does to the
    /// finished one.
    func pencilKitStroke(predicted: [InkSample] = [], transform: CGAffineTransform = .identity) -> PKStroke {
        var points = (snap == nil ? samples + predicted : drawnSamples).map(style.point(for:))
        // A masked stroke of one or two points is how a paint bucket fill
        // looks (`ExquisiteCorpseFold`), so a dashed or dotted tap repeats
        // its point.
        if style.lineStyle != .solid, points.count < 3 {
            points += repeatElement(points[points.count - 1], count: 3 - points.count)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: creationDate)
        return PKStroke(
            ink: style.ink,
            path: path,
            transform: transform,
            mask: style.dashMask(along: path, isClosed: snap?.shape.isClosed ?? false),
            randomSeed: seed
        )
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        values.sorted()[values.count / 2]
    }
}
