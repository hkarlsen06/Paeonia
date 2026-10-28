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
            let outward = origin / max(distance, 0.000001)
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
    let variation: Double
    let initialPosition: SIMD3<Double>
    let driftPhase: Double
    let driftRate: Double

    init(index: Int) {
        self.index = index
        variation = Self.random(index, salt: 3.71)
        let azimuth = Double(index) * 2.3999632297
        let latitude = 2 * Self.random(index, salt: 5.37) - 1
        let radial = sqrt(1 - latitude * latitude)
        let radius = pow(Self.random(index, salt: 8.13), 0.45)
        initialPosition = SIMD3(cos(azimuth) * radial * radius,
                                latitude * radius * 0.9,
                                sin(azimuth) * radial * radius)
        driftPhase = Self.random(index, salt: 2.17) * 2 * .pi
        driftRate = 0.35 + Self.random(index, salt: 6.41) * 0.4
    }

    var size: Double { 0.8 + variation * 1.9 }

    func orbit(elapsed: Double, progress: Double) -> SIMD3<Double> {
        let contraction = pow(1 - progress, 1.65)
        let distance = 0.045 + 0.955 * contraction
        let turn = elapsed * (0.12 + variation * 0.09) + progress * progress * 0.7
        let tilt = elapsed * (0.08 + variation * 0.05)
        let drift = elapsed * driftRate + driftPhase
        let source = initialPosition + SIMD3(
            sin(drift) * 0.045, cos(drift * 0.83) * 0.05, sin(drift * 0.71) * 0.045)
        let rotatedX = source.x * cos(turn) + source.z * sin(turn)
        let rotatedZ = source.z * cos(turn) - source.x * sin(turn)
        return SIMD3(rotatedX, source.y * cos(tilt) - rotatedZ * sin(tilt),
                     source.y * sin(tilt) + rotatedZ * cos(tilt)) * distance
    }

    private static func random(_ index: Int, salt: Double) -> Double {
        let value = sin(Double(index) * salt + salt) * 43_758.5453
        return value - floor(value)
    }
}

struct PairingCelebrationParticleProjection {
    let size: CGSize

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * PairingCelebrationTiming.centerYRatio) }
    var radius: Double { min(size.width / 2, center.y, size.height - center.y) * 0.65 }

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
