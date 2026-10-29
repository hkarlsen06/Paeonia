import CoreGraphics
import Foundation
import simd

struct PairingCelebrationParticlePlayback {
    struct Absorption {
        let since: Double
        let duration: Double
    }

    enum Stage {
        case appearing
        case absorbing(Absorption)
        case bursting(absorption: Absorption, since: Double, releaseDuration: Double)
    }

    var started: Double
    var heartIsVisibleAtStart = false
    var stage: Stage = .appearing

    func position(seed: PairingCelebrationParticleSeed, at time: Double,
                  closingRadius: Double = 0.026) -> SIMD3<Double> {
        switch stage {
        case .appearing:
            return seed.orbit(elapsed: time - started, gatherElapsed: 0, duration: 1, closingRadius: closingRadius)
        case let .absorbing(absorption):
            return inward(seed: seed, at: time, absorption: absorption, closingRadius: closingRadius)
        case let .bursting(absorption, since, releaseDuration):
            if time < since {
                return inward(seed: seed, at: time, absorption: absorption, closingRadius: closingRadius)
            }
            let origin = inward(seed: seed, at: since, absorption: absorption, closingRadius: closingRadius)
            let previous = inward(seed: seed, at: since - 0.002, absorption: absorption, closingRadius: closingRadius)
            let velocity = (origin - previous) / 0.002
            let elapsed = time - since
            let progress = elapsed / max(releaseDuration, 0.001)
            let distance = sqrt(origin.x * origin.x + origin.y * origin.y + origin.z * origin.z)
            let outward = origin / max(distance, 0.000001)
            let travel = (1 - (1 + progress * 3) * exp(-progress * 3)) * (2.0 + seed.variation * 0.7)
            return origin + velocity * ((1 - exp(-elapsed * 2)) / 2) + outward * travel
        }
    }

    func gatherShape(at time: Double) -> PairingCelebrationGatherShape {
        PairingCelebrationGatherShape(progress: gatherProgress(at: time))
    }

    func sparkOpacity(seed: PairingCelebrationParticleSeed, at time: Double) -> Double {
        guard case let .bursting(_, since, duration) = stage else { return 1 }
        let progress = max(0, (time - since) / max(duration, 0.001))
        let lifetime = 0.70 + seed.variation * 0.25
        return 1 - Self.smoothstep((progress - lifetime * 0.40) / (lifetime * 0.60))
    }

    func opacity(at time: Double) -> Double {
        let appear = min(max((time - started) / 0.4, 0), 1)
        if case let .bursting(_, since, duration) = stage {
            let progress = max(0, (time - since) / max(duration, 0.001))
            return appear * (1 - Self.smoothstep((progress - 0.18) / 0.82))
        }
        return appear
    }

    func heartOpacity(at time: Double) -> Double {
        (heartIsVisibleAtStart ? 1 : opacity(at: time)) * gatherShape(at: time).heartOpacity
    }

    func gatherProgress(at time: Double) -> Double {
        switch stage {
        case .appearing: return 0
        case let .absorbing(absorption), let .bursting(absorption, _, _):
            return min(max((time - absorption.since) / absorption.duration, 0), 1)
        }
    }

    private func inward(
        seed: PairingCelebrationParticleSeed, at time: Double, absorption: Absorption,
        closingRadius: Double
    ) -> SIMD3<Double> {
        seed.orbit(elapsed: time - started, gatherElapsed: max(0, time - absorption.since),
                   duration: max(absorption.duration, 0.001), closingRadius: closingRadius)
    }

    static func smoothstep(_ value: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }
}

struct PairingCelebrationGatherShape {
    static let coverStart = 0.26
    static let coverComplete = 0.65
    static let heartHidden = 0.72
    static let compressionStart = 0.78
    static let compressionComplete = 0.98

    let progress: Double

    var cover: Double {
        PairingCelebrationParticlePlayback.smoothstep(
            (progress - Self.coverStart) / (Self.coverComplete - Self.coverStart))
    }

    var compression: Double {
        PairingCelebrationParticlePlayback.smoothstep(
            (progress - Self.compressionStart) / (Self.compressionComplete - Self.compressionStart))
    }

    var heartOpacity: Double {
        1 - PairingCelebrationParticlePlayback.smoothstep(
            (progress - 0.54) / (Self.heartHidden - 0.54))
    }
}

struct PairingCelebrationParticleSeed {
    let index: Int
    let variation: Double
    let direction: SIMD3<Double>
    let speed: Double
    let shellRadius: Double

    var isDust: Bool { index >= 240 }

    init(index: Int) {
        self.index = index
        let pair = index / 2
        variation = Self.random(pair, salt: 3.71)
        // Every direction has an opposite with the same radius and angular speed.
        // Orthographic projection preserves that balance at every sampled time.
        let latitude = index < 240
            ? (Double(pair) + 0.5) / 120
            : (Double(pair - 120) + 0.5) / 200
        let azimuth = Double(pair) * 2.3999632297
        let transverse = sqrt(1 - latitude * latitude)
        let sign = index.isMultiple(of: 2) ? 1.0 : -1.0
        direction = SIMD3(transverse * cos(azimuth), transverse * sin(azimuth), latitude) * sign
        speed = 0.97 + Self.random(pair, salt: 6.41) * 0.06
        shellRadius = index < 240
            ? 0.82 + Self.random(pair, salt: 8.13) * 0.18
            : 0.16 + pow(Self.random(pair, salt: 8.13), 0.6) * 0.74
    }

    var size: Double { isDust ? 0.7 + variation * 1.1 : 1.0 + variation * 1.1 }

    func orbit(elapsed: Double, gatherElapsed: Double, duration: Double,
               closingRadius: Double) -> SIMD3<Double> {
        let progress = min(gatherElapsed / duration, 1)
        let shape = PairingCelebrationGatherShape(progress: progress)
        let broad = PairingCelebrationParticlePlayback.smoothstep(progress / 0.70)
        let shell = shellRadius * (1 - 0.43 * broad)
        let radius = shell * (1 - shape.compression) + closingRadius * shellRadius * shape.compression
        let accelerationDuration = duration * 0.72
        let ramp = min(gatherElapsed / accelerationDuration, 1)
        let extraAngle = 4.0 * (accelerationDuration * (pow(ramp, 3) - 0.5 * pow(ramp, 4))
            + max(0, gatherElapsed - accelerationDuration))
        let angle = speed * (max(0, elapsed) * 1.25 + extraAngle)
        let axis = simd_normalize(SIMD3<Double>(0.32, 0.79, 0.52))
        let rotated = direction * cos(angle) + simd_cross(axis, direction) * sin(angle)
            + axis * simd_dot(axis, direction) * (1 - cos(angle))
        return radius * rotated
    }

    private static func random(_ index: Int, salt: Double) -> Double {
        let value = sin(Double(index) * salt + salt) * 43_758.5453
        return value - floor(value)
    }
}

struct PairingCelebrationParticleProjection {
    let size: CGSize

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * PairingCelebrationTiming.centerYRatio) }
    var radius: Double { min(115, min(size.width / 2, center.y, size.height - center.y) * 0.65) }
    var closingRadius: Double { 0.6 / max(radius, 1) }

    func point(_ position: SIMD3<Double>) -> CGPoint {
        CGPoint(x: center.x + position.x * radius, y: center.y + position.y * radius)
    }

    func burstVisibility(points: [CGPoint], extent: Double, seed: PairingCelebrationParticleSeed) -> Double {
        let inscribed = min(size.width / 2, center.y, size.height - center.y)
        let available = max(1, inscribed - extent - 24)
        let end = available * (0.70 + seed.variation * 0.28)
        let start = end * (0.40 + seed.variation * 0.20)
        let distance = points.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
        return 1 - PairingCelebrationParticlePlayback.smoothstep((distance - start) / (end - start))
    }

    func visibility(points: [CGPoint], extent: Double) -> Double {
        let clearance = points.reduce(Double.infinity) { result, point in
            min(result, point.x, size.width - point.x, point.y, size.height - point.y)
        } - extent
        let progress = min(max(clearance / max(24, radius * 0.2), 0), 1)
        return progress * progress * (3 - 2 * progress)
    }
}
