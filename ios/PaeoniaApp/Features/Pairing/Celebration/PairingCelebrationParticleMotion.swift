import CoreGraphics
import Foundation

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

    func position(seed: PairingCelebrationParticleSeed, at time: Double) -> SIMD3<Double> {
        switch stage {
        case .appearing:
            return seed.orbit(elapsed: time - started, progress: 0)
        case let .absorbing(absorption):
            return inward(seed: seed, at: time, absorption: absorption)
        case let .bursting(absorption, since, releaseDuration):
            if time < since {
                return inward(seed: seed, at: time, absorption: absorption)
            }
            let origin = inward(seed: seed, at: since, absorption: absorption)
            let previous = inward(seed: seed, at: since - 0.002, absorption: absorption)
            let velocity = (origin - previous) / 0.002
            let elapsed = time - since
            let progress = min(elapsed / max(releaseDuration, 0.001), 1)
            let distance = sqrt(origin.x * origin.x + origin.y * origin.y + origin.z * origin.z)
            let outward = origin / distance
            return origin + velocity * elapsed * exp(-elapsed * 3)
                + outward * (progress * progress * (1.15 + seed.variation * 0.65))
        }
    }

    func opacity(at time: Double) -> Double {
        let appear = min(max((time - started) / 0.4, 0), 1)
        if case let .bursting(_, since, duration) = stage {
            return appear * pow(max(0, 1 - (time - since) / max(duration, 0.001)), 1.5)
        }
        return appear
    }

    private func inward(
        seed: PairingCelebrationParticleSeed, at time: Double, absorption: Absorption
    ) -> SIMD3<Double> {
        let progress = min(max((time - absorption.since) / max(absorption.duration, 0.001), 0), 1)
        return seed.orbit(elapsed: time - started, progress: progress)
    }
}

struct PairingCelebrationParticleSeed {
    let index: Int
    let angle: Double
    let variation: Double
    let radius: Double

    init(index: Int) {
        self.index = index
        angle = Double(index) * 2.3999632297
        variation = Self.random(index, salt: 3.71)
        radius = 0.58 + Self.random(index, salt: 8.13) * 0.48
    }

    var size: Double { index % 5 == 0 ? 0.9 : 2.1 + variation * 2.5 }

    func orbit(elapsed: Double, progress: Double) -> SIMD3<Double> {
        let contraction = pow(1 - progress, 1.65)
        let distance = radius * (0.045 + 0.955 * contraction)
        let rotation = angle + elapsed * (1.3 + variation * 0.3) + progress * progress * 4.2
        let horizontal = cos(rotation) * distance
        let vertical = sin(rotation) * distance
        let elevation = sin(angle * 3) * distance * 0.12
        let tiltedY = vertical * 0.48 - elevation * 0.88
        return SIMD3(horizontal * 0.94 - tiltedY * 0.34,
                     horizontal * 0.34 + tiltedY * 0.94,
                     vertical * 0.88 + elevation * 0.48)
    }

    private static func random(_ index: Int, salt: Double) -> Double {
        let value = sin(Double(index) * salt + salt) * 43_758.5453
        return value - floor(value)
    }
}
