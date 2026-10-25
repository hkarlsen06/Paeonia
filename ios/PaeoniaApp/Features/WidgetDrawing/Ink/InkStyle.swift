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

    /// How thick the line on the canvas is for `width`. Monoline draws twice
    /// the width. Rendering the points of real finger strokes gave lines of
    /// 2, 11 and 24 points for widths 1, 5.4 and 12. The pencil draws about
    /// the width it is given.
    func drawnWidth(_ width: CGFloat) -> CGFloat {
        switch self {
        case .pen:
            width * 2
        case .pencil:
            width
        }
    }

    /// How wide each dot of a dotted line is for `width`. A pen dot is as
    /// wide as the line. Pencil ink thins out toward its edges, so a dot as
    /// wide as the line came out flat at the top and bottom. Rendered at
    /// width 16, dots were still flat at 0.85 of the width and round at 0.8.
    func dotDiameter(_ width: CGFloat) -> CGFloat {
        switch self {
        case .pen:
            drawnWidth(width)
        case .pencil:
            width * 0.8
        }
    }

    /// How far the middle of the line sits from its points, toward each
    /// point's azimuth. Rendering pencil strokes of widths 2.4 to 16 gave ink
    /// from about a quarter of the width behind the points to three quarters
    /// of it ahead, less a point. A finger's azimuth points down the screen,
    /// so its pencil line sits below the finger.
    func inkOffset(_ width: CGFloat) -> CGFloat {
        switch self {
        case .pen:
            0
        case .pencil:
            max(0, width / 4 - 0.5)
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
    var lineStyle: InkLineStyle

    var ink: PKInk {
        PKInk(kind.inkType, color: color)
    }

    /// The ink a dashed or dotted line keeps along `path`, in the path's own
    /// space, or nil for a solid line. `isClosed` is for a snapped shape
    /// that ends where it starts.
    func dashMask(along path: PKStrokePath, isClosed: Bool) -> UIBezierPath? {
        let lineWidth = lineStyle == .dotted ? kind.dotDiameter(width) : kind.drawnWidth(width)
        guard let pattern = lineStyle.pattern(lineWidth: lineWidth) else {
            return nil
        }
        let offset = kind.inkOffset(width)
        let centerline = path.interpolatedPoints(by: .distance(InkDashMask.sampleSpacing)).map { point in
            CGPoint(
                x: point.location.x + offset * cos(point.azimuth),
                y: point.location.y + offset * sin(point.azimuth)
            )
        }
        return UIBezierPath(cgPath: InkDashMask.path(
            centerline: centerline,
            pattern: pattern,
            width: lineWidth,
            isClosed: isClosed
        ))
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
