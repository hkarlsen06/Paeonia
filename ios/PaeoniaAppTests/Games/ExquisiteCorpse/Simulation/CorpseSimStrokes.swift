import Foundation
import PencilKit
@testable import PaeoniaApp

/// Strokes for the drawer on a canvas of `side` points, placed relative to the
/// fold at 88% of the height.
enum CorpseSimStrokes {
    enum Zone: CaseIterable {
        /// Ends above the fold, so none of it reaches the strip.
        case above
        /// Starts above the fold and ends below it.
        case crossing
        case below
        case anywhere
    }

    /// Gives every stroke its own creation time, which keys it in the live strip.
    nonisolated(unsafe) private static var created = 5_000.0

    static func stroke(seed: inout SimRandom, side: CGFloat, zone: Zone) -> PKStroke {
        let range: ClosedRange<Double> = switch zone {
        case .above: 0.05...0.84
        case .crossing: 0.78...0.97
        case .below: 0.9...0.98
        case .anywhere: 0.05...0.98
        }
        let count = seed.int(3...8)
        var x = CGFloat(0.1 + seed.unit() * 0.8) * side
        var points: [PKStrokePoint] = []
        for index in 0..<count {
            var fraction = range.lowerBound + seed.unit() * (range.upperBound - range.lowerBound)
            if zone == .crossing, index == 0 { fraction = 0.8 }
            if zone == .crossing, index == count - 1 { fraction = 0.96 }
            points.append(PKStrokePoint(
                location: CGPoint(x: x, y: CGFloat(fraction) * side),
                timeOffset: TimeInterval(index) * 0.03,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ))
            x = min(side - 2, max(2, x + CGFloat(seed.unit() - 0.5) * 40))
        }
        created += 0.05
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: created))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }
}
