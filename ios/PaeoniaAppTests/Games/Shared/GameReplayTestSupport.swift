import PencilKit
import UIKit

/// Builds strokes with exact creation dates and point times.
enum ReplayFixtures {
    static let epoch = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// A stroke that starts at `created` (seconds after `epoch`) and runs along
    /// y = `y`, with `offsets` as the point times and x = `offset * 10`.
    static func stroke(
        created: TimeInterval,
        offsets: [TimeInterval],
        y: CGFloat = 0,
        ink: PKInk = PKInk(.pen, color: .black),
        transform: CGAffineTransform = .identity,
        mask: UIBezierPath? = nil
    ) -> PKStroke {
        let points = offsets.map { offset in
            PKStrokePoint(
                location: CGPoint(x: offset * 10, y: y),
                timeOffset: offset,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: ink,
            path: PKStrokePath(controlPoints: points, creationDate: epoch.addingTimeInterval(created)),
            transform: transform,
            mask: mask
        )
    }

    static func drawing(_ strokes: PKStroke...) -> PKDrawing {
        PKDrawing(strokes: strokes)
    }
}
