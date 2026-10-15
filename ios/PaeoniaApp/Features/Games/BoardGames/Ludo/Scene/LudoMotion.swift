import Foundation
import simd

/// The paths of the Ludo animations as pure functions of time, so they are
/// testable. The thrown die has its own simulation in `LudoDiePhysics`.
/// Positions are in world units.
nonisolated enum LudoMotion {
    static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Eases in and out, 0 to 1.
    static func smooth(_ value: Double) -> Double {
        let fraction = clamped(value)
        return fraction * fraction * (3 - 2 * fraction)
    }

    // MARK: Pawn

    /// A hop from one point to another: straight along the board with an arc on top.
    static func hop(from start: SIMD3<Float>, to end: SIMD3<Float>, progress: Double, arc: Float) -> SIMD3<Float> {
        let fraction = Float(clamped(progress))
        var position = start + (end - start) * fraction
        position.y += arc * 4 * fraction * (1 - fraction)
        return position
    }

    /// A pawn walking through `points`, one hop for each gap.
    static func hops(through points: [SIMD3<Float>], elapsed: Double, hopDuration: Double, arc: Float) -> SIMD3<Float> {
        guard let first = points.first else { return .zero }
        guard points.count > 1, hopDuration > 0 else { return points.last ?? first }
        let steps = points.count - 1
        let index = min(max(Int(elapsed / hopDuration), 0), steps - 1)
        let local = (elapsed - Double(index) * hopDuration) / hopDuration
        return hop(from: points[index], to: points[index + 1], progress: local, arc: arc)
    }

    /// A pawn sent home: it pops up, arcs back to its base and settles with a small bounce.
    static func sendHome(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        elapsed: Double,
        duration: Double
    ) -> SIMD3<Float> {
        let settle = 0.14
        let flight = max(duration - settle, 0.01)
        if elapsed < flight {
            let fraction = clamped(elapsed / flight)
            var position = start + (end - start) * Float(smooth(fraction))
            position.y += LudoSceneStyle.sendHomeArc * Float(4 * fraction * (1 - fraction))
            return position
        }
        let fraction = clamped((elapsed - flight) / settle)
        var position = end
        position.y += 0.12 * Float(4 * fraction * (1 - fraction))
        return position
    }

    /// Sideways wobble of a pawn that cannot move, as an offset along x.
    static func shake(progress: Double) -> Float {
        let fraction = clamped(progress)
        return LudoSceneStyle.shakeDistance * Float(sin(fraction * 2 * .pi * 3) * (1 - fraction))
    }

    // MARK: Die

    /// A die changing yards: a hop with an arc.
    static func trayHop(from start: SIMD3<Float>, to end: SIMD3<Float>, progress: Double) -> SIMD3<Float> {
        let fraction = clamped(progress)
        var position = start + (end - start) * Float(smooth(fraction))
        position.y += LudoSceneStyle.trayHopArc * Float(4 * fraction * (1 - fraction))
        return position
    }
}
