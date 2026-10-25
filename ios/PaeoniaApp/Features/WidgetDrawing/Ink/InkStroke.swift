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
    let style: InkStyle
    /// The pencil texture's seed. Fixed per stroke, so the texture holds still
    /// while the stroke grows and when it lands on the canvas.
    let seed: UInt32
    /// With the seed and the point count, this names the stroke on both phones
    /// (`WidgetLiveStrokeSync.key`).
    let creationDate: Date
    private(set) var samples: [InkSample]

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

    /// The stroke as far as it was drawn `elapsed` seconds in, or nil before
    /// its first sample.
    func prefix(through elapsed: TimeInterval) -> InkStroke? {
        let shown = samples.prefix { $0.timeOffset <= elapsed }
        guard !shown.isEmpty else {
            return nil
        }
        var stroke = self
        stroke.samples = Array(shown)
        return stroke
    }

    /// The PencilKit stroke. `predicted` samples come only from the wet ink on
    /// this phone and never reach the finished stroke. `transform` scales a
    /// partner's stroke to this canvas, as `PKDrawing.scaled` does to the
    /// finished one.
    func pencilKitStroke(predicted: [InkSample] = [], transform: CGAffineTransform = .identity) -> PKStroke {
        let points = (samples + predicted).map(style.point(for:))
        return PKStroke(
            ink: style.ink,
            path: PKStrokePath(controlPoints: points, creationDate: creationDate),
            transform: transform,
            mask: nil,
            randomSeed: seed
        )
    }
}
