import PencilKit
import UIKit

/// The ink of a pen or pencil stroke.
nonisolated enum InkKind: String, Codable, Sendable {
    case pen
    case pencil

    var inkType: PKInk.InkType {
        switch self {
        case .pen:
            // PencilKit's `.pen` ink sizes finger strokes by speed and mostly
            // ignores the width. Monoline keeps a steady width.
            .monoline
        case .pencil:
            .pencil
        }
    }

    /// The widths the size slider gives this ink, in canvas points. Monoline
    /// reports `0.5...4`, too thin to be useful, but it takes wider widths too,
    /// so the pen sets its own.
    var validWidthRange: ClosedRange<CGFloat> {
        switch self {
        case .pen:
            1...12
        case .pencil:
            PKInkingTool.InkType.pencil.validWidthRange
        }
    }
}

/// Everything that decides how an ink stroke looks. It is taken when the
/// finger touches down, so a tool change during the stroke never restyles it.
nonisolated struct InkStyle: Equatable, Sendable {
    var kind: InkKind
    var color: UIColor
    /// The width the size slider gives, in canvas points.
    var width: CGFloat

    var ink: PKInk {
        PKInk(kind.inkType, color: color)
    }

    /// The PencilKit point for one sample.
    ///
    /// These are the attributes PencilKit gave finger strokes drawn with its
    /// own drawing gesture (logged on the simulator, iOS 27.0, for every
    /// width). Monoline points are 2 points wider than the width. Pencil
    /// points grow from 1.2 to 4 points across the pencil's width range, at
    /// half opacity, with a jitter of up to 8. Both have a secondary scale of
    /// one over the size.
    func point(for sample: InkSample) -> PKStrokePoint {
        let size: CGFloat
        let opacity: CGFloat
        let lateralJitter: CGFloat
        switch kind {
        case .pen:
            size = width + 2
            opacity = 1
            lateralJitter = 0
        case .pencil:
            let range = kind.validWidthRange
            let fraction = (width - range.lowerBound) / (range.upperBound - range.lowerBound)
            size = 1.2 + 2.8 * fraction
            opacity = 0.5
            lateralJitter = (80 * fraction).rounded() / 10
        }
        // A finger has no pressure or tilt. PencilKit gave its points these.
        let isFinger = sample.force == nil
        return PKStrokePoint(
            location: sample.location,
            timeOffset: sample.timeOffset,
            size: CGSize(width: size, height: size),
            opacity: opacity,
            force: sample.force ?? 0,
            azimuth: isFinger ? .pi / 2 : sample.azimuth,
            altitude: isFinger ? .pi / 2 : sample.altitude,
            secondaryScale: 1 / size,
            threshold: 0,
            lateralJitter: lateralJitter
        )
    }
}
