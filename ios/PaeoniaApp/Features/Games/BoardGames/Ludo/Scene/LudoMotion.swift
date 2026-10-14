import Foundation
import simd

/// The paths of the Ludo animations as pure functions of time, so they are
/// testable and a clip never needs physics. Positions are in world units.
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

    /// When the die touches down, as a share of the tumble. The last one is 1.
    static func tumbleLandings() -> [Double] {
        var total = 0.0
        return LudoSceneStyle.bounceShares.map {
            total += $0
            return total
        }
    }

    /// How high the die is above the yard floor, through the bounces of the tumble.
    static func tumbleHeight(progress: Double) -> Float {
        let fraction = clamped(progress)
        var start = 0.0
        for (share, peak) in zip(LudoSceneStyle.bounceShares, LudoSceneStyle.bouncePeaks) {
            if fraction < start + share {
                let local = (fraction - start) / share
                return peak * Float(4 * local * (1 - local))
            }
            start += share
        }
        return 0
    }

    /// Where the die is during the tumble. It travels from `start` to its resting place at
    /// `end`, drifts to the side and bounces. At progress 1 it is exactly at `end`.
    static func tumblePosition(from start: SIMD3<Float>, to end: SIMD3<Float>, progress: Double) -> SIMD3<Float> {
        let fraction = clamped(progress)
        guard fraction < 1 else { return end }
        var position = start + (end - start) * Float(smooth(fraction))
        position.y += tumbleHeight(progress: fraction)
        position.x += LudoSceneStyle.tumbleDriftX * Float(sin(fraction * 2 * .pi))
        let towardBoard: Float = end.z > 0 ? -1 : 1
        position.z += towardBoard * LudoSceneStyle.tumbleDriftZ * Float(sin(fraction * .pi))
        return position
    }

    /// How the die is turned during the tumble. It spins fast, slows down and ends
    /// exactly in `final`. The spin is a whole number of turns at the start, so
    /// the die begins in the pose it had.
    static func tumbleOrientation(from start: simd_quatf, to final: simd_quatf, progress: Double) -> simd_quatf {
        let fraction = clamped(progress)
        guard fraction < 1 else { return final }
        let base = simd_slerp(start, final, Float(smooth(fraction)))
        let remaining = 1 - fraction
        let angle = Float(LudoSceneStyle.tumbleTurns * 2 * .pi * remaining * remaining)
        let spin = simd_quatf(angle: angle, axis: simd_normalize(LudoSceneStyle.tumbleAxis))
        return spin * base
    }

    /// A die changing yards: a hop with an arc.
    static func trayHop(from start: SIMD3<Float>, to end: SIMD3<Float>, progress: Double) -> SIMD3<Float> {
        let fraction = clamped(progress)
        var position = start + (end - start) * Float(smooth(fraction))
        position.y += LudoSceneStyle.trayHopArc * Float(4 * fraction * (1 - fraction))
        return position
    }
}
