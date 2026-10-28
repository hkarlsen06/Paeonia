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
    var stage: Stage = .appearing

    func position(seed: PairingCelebrationParticleSeed, at time: Double,
                  closingRadius: Double = 0.52) -> SIMD3<Double> {
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
            let progress = min(elapsed / max(releaseDuration, 0.001), 1)
            let distance = sqrt(origin.x * origin.x + origin.y * origin.y + origin.z * origin.z)
            let outward = origin / max(distance, 0.000001)
            return origin + velocity * ((1 - exp(-elapsed * 2)) / 2)
                + outward * ((progress - 0.16 * (1 - exp(-progress / 0.16))) * (2.4 + seed.variation * 0.8))
        }
    }

    func opacity(at time: Double) -> Double {
        let appear = min(max((time - started) / 0.4, 0), 1)
        if case let .bursting(_, since, duration) = stage {
            let progress = max(0, (time - since) / max(duration, 0.001))
            return appear * (1 - Self.smoothstep((progress - 0.18) / 0.82))
        }
        return appear
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

struct PairingCelebrationParticleSeed {
    let index: Int
    let variation: Double
    let orbitalU: SIMD3<Double>
    let orbitalV: SIMD3<Double>
    let phase: Double
    let speed: Double
    let shellRadius: Double

    init(index: Int) {
        self.index = index
        variation = Self.random(index, salt: 3.71)
        let axis = simd_normalize(SIMD3<Double>(0.25, 0.45, 0.86))
        let across = simd_normalize(simd_cross(axis, SIMD3(0, 1, 0)))
        let around = simd_cross(axis, across)
        let azimuth = Double(index) * 2.3999632297
        let inclination = (45 + 15 * Self.random(index, salt: 5.37)) * .pi / 180
        let normal = axis * cos(inclination)
            + (across * cos(azimuth) + around * sin(azimuth)) * sin(inclination)
        orbitalU = simd_normalize(simd_cross(normal, axis))
        orbitalV = simd_cross(normal, orbitalU)
        phase = Self.random(index, salt: 2.17) * 2 * .pi
        speed = 0.88 + Self.random(index, salt: 6.41) * 0.24
        shellRadius = 0.78 + Self.random(index, salt: 8.13) * 0.42
    }

    var size: Double { 1.1 + variation * 1.4 }

    func orbit(elapsed: Double, gatherElapsed: Double, duration: Double,
               closingRadius: Double) -> SIMD3<Double> {
        let progress = min(gatherElapsed / duration, 1)
        let broad = PairingCelebrationParticlePlayback.smoothstep(progress / (1.7 / 3.5))
        let envelop = PairingCelebrationParticlePlayback.smoothstep((progress - 1.7 / 3.5) / (1.3 / 3.5))
        let shoulder = 0.77
        let radius = (1 - (1 - shoulder) * broad - (shoulder - closingRadius) * envelop)
            * shellRadius * (1 + 0.025 * sin(elapsed * 1.2 + phase))
        let accelerationDuration = duration * 0.72
        let ramp = min(gatherElapsed / accelerationDuration, 1)
        let extraAngle = 3.2 * (accelerationDuration * (pow(ramp, 3) - 0.5 * pow(ramp, 4))
            + max(0, gatherElapsed - accelerationDuration))
        let angle = phase + speed * (elapsed * 1.8 + extraAngle)
        return radius * (orbitalU * cos(angle) + orbitalV * sin(angle))
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
    var closingRadius: Double { min(0.78, Double(PairingCelebrationTiming.heartSize) * (5.0 / 6) / max(radius, 1)) }

    func perspective(_ position: SIMD3<Double>) -> Double {
        1 / max(0.35, 1 - position.z * 0.2)
    }

    func point(_ position: SIMD3<Double>) -> CGPoint {
        let scale = radius * perspective(position)
        return CGPoint(x: center.x + position.x * scale, y: center.y + position.y * scale)
    }

    func visibility(points: [CGPoint], extent: Double) -> Double {
        let clearance = points.reduce(Double.infinity) { result, point in
            min(result, point.x, size.width - point.x, point.y, size.height - point.y)
        } - extent
        let progress = min(max(clearance / max(24, radius * 0.2), 0), 1)
        return progress * progress * (3 - 2 * progress)
    }
}
