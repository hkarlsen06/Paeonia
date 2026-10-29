import CoreGraphics
import Foundation
import simd

struct PairingCelebrationParticlePlayback {
    struct Absorption {
        let since: Double
        let duration: Double
        var releaseDuration = PairingCelebrationTiming.explode

        var impact: Double { since + duration }
    }

    enum Stage {
        case appearing
        case absorbing(Absorption)
    }

    var started: Double
    var heartIsVisibleAtStart = false
    var stage: Stage = .appearing

    struct SampleFrame {
        struct Burst {
            let origin: PairingCelebrationParticleSeed.Orbit
            let previous: PairingCelebrationParticleSeed.Orbit
            let tangentScale: Double
            let travel: Double
        }

        enum Motion {
            case orbit(PairingCelebrationParticleSeed.Orbit)
            case burst(Burst)
        }

        let motion: Motion

        init(playback: PairingCelebrationParticlePlayback, time: Double, closingRadius: Double) {
            func orbit(gatherElapsed: Double, at time: Double,
                       duration: Double) -> PairingCelebrationParticleSeed.Orbit {
                .init(elapsed: time - playback.started, gatherElapsed: gatherElapsed,
                      duration: duration, closingRadius: closingRadius)
            }
            switch playback.stage {
            case .appearing:
                motion = .orbit(orbit(gatherElapsed: 0, at: time, duration: 1))
            case let .absorbing(absorption):
                let duration = max(absorption.duration, 0.001)
                if time < absorption.impact {
                    motion = .orbit(orbit(gatherElapsed: max(0, time - absorption.since), at: time, duration: duration))
                } else {
                    let elapsed = time - absorption.impact
                    motion = .burst(Burst(
                        origin: orbit(gatherElapsed: max(0, absorption.impact - absorption.since),
                                      at: absorption.impact, duration: duration),
                        previous: orbit(gatherElapsed: max(0, absorption.impact - 0.0001 - absorption.since),
                                        at: absorption.impact - 0.0001, duration: duration),
                        tangentScale: (1 - exp(-elapsed * 2)) / 2,
                        travel: 1 - exp(-elapsed / absorption.releaseDuration * 2.6)))
                }
            }
        }
    }

    private struct BurstGeometry {
        let origin: SIMD3<Double>
        let outward: SIMD3<Double>
        let tangent: SIMD3<Double>
    }

    func history(seed: PairingCelebrationParticleSeed, frames: ArraySlice<SampleFrame>) -> [SIMD3<Double>] {
        var burst: BurstGeometry?
        return frames.map { frame in
            switch frame.motion {
            case let .orbit(orbit):
                return orbit.position(seed: seed)
            case let .burst(frame):
                if burst == nil {
                    let origin = frame.origin.position(seed: seed)
                    let previous = frame.previous.position(seed: seed)
                    let velocity = (origin - previous) / 0.0001
                    let outward = simd_normalize(origin)
                    burst = BurstGeometry(origin: origin, outward: outward,
                                          tangent: velocity - outward * simd_dot(velocity, outward))
                }
                guard let burst else { preconditionFailure("Missing burst geometry") }
                return burst.origin + burst.tangent * frame.tangentScale
                    + burst.outward * (frame.travel * (1.6 + seed.variation * 0.7))
            }
        }
    }

    func gatherShape(at time: Double) -> PairingCelebrationGatherShape {
        PairingCelebrationGatherShape(progress: gatherProgress(at: time))
    }

    func sparkOpacity(seed: PairingCelebrationParticleSeed, at time: Double) -> Double {
        guard let progress = releaseProgress(at: time) else { return 1 }
        let lifetime = 0.70 + seed.variation * 0.25
        return 1 - Self.smoothstep((progress - lifetime * 0.40) / (lifetime * 0.60))
    }

    func opacity(at time: Double) -> Double {
        let appear = min(max((time - started) / 0.4, 0), 1)
        if let progress = releaseProgress(at: time) {
            return appear * (1 - Self.smoothstep((progress - 0.18) / 0.82))
        }
        return appear
    }

    func heartOpacity(at time: Double) -> Double {
        guard releaseProgress(at: time) == nil else { return 0 }
        return heartIsVisibleAtStart ? 1 : opacity(at: time)
    }

    func gatherProgress(at time: Double) -> Double {
        switch stage {
        case .appearing: return 0
        case let .absorbing(absorption):
            return min(max((time - absorption.since) / absorption.duration, 0), 1)
        }
    }

    func releaseProgress(at time: Double) -> Double? {
        guard case let .absorbing(absorption) = stage, time >= absorption.impact else { return nil }
        return (time - absorption.impact) / absorption.releaseDuration
    }

    func radius(at time: Double, closingRadius: Double) -> Double {
        if let progress = releaseProgress(at: time) {
            return closingRadius + (1 - exp(-progress * 2.6)) * 1.95
        }
        return closingRadius + (1 - closingRadius) * gatherShape(at: time).radius
    }

    static func smoothstep(_ value: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }
}

struct PairingCelebrationGatherShape {
    let progress: Double

    var cover: Double {
        PairingCelebrationParticlePlayback.smoothstep((progress - 0.12) / 0.42)
    }

    var radius: Double {
        let time = min(max(progress, 0), 1)
        let pullStart = 0.73
        let initialTravel = 0.16
        guard time > pullStart else {
            return 1 - initialTravel * pow(time / pullStart, 2)
        }
        // Carry the inward velocity into the fall instead of easing to a stop.
        let speed = 2 * initialTravel / pullStart
        let fallDuration = 1 - pullStart
        let acceleration = 2 * (1 - initialTravel - speed * fallDuration) / pow(fallDuration, 2)
        let fall = time - pullStart
        return max(0, 1 - initialTravel - speed * fall - 0.5 * acceleration * fall * fall)
    }
}

struct PairingCelebrationParticleSeed {
    let index: Int
    let variation: Double
    let direction: SIMD3<Double>
    let speed: Double
    let axisCrossDirection: SIMD3<Double>
    let axisProjection: SIMD3<Double>
    let shellRadius: Double

    static let starCount = 240
    static let dustCount = 2_000

    var isDust: Bool { index >= Self.starCount }

    init(index: Int) {
        self.index = index
        let pair = index / 2
        variation = Self.random(pair, salt: 3.71)
        // Every direction has an opposite with the same radius and angular speed.
        // Orthographic projection preserves that balance at every sampled time.
        let latitude = index < Self.starCount
            ? (Double(pair) + 0.5) / Double(Self.starCount / 2)
            : (Double(pair - Self.starCount / 2) + 0.5) / Double(Self.dustCount / 2)
        let azimuth = Double(pair) * 2.3999632297
        let transverse = sqrt(1 - latitude * latitude)
        let sign = index.isMultiple(of: 2) ? 1.0 : -1.0
        direction = SIMD3(transverse * cos(azimuth), transverse * sin(azimuth), latitude) * sign
        let axis = simd_normalize(SIMD3<Double>(0.32, 0.79, 0.52))
        axisCrossDirection = simd_cross(axis, direction)
        axisProjection = axis * simd_dot(axis, direction)
        speed = 0.97 + Self.random(pair, salt: 6.41) * 0.06
        shellRadius = index < Self.starCount
            ? 0.82 + Self.random(pair, salt: 8.13) * 0.18
            : 0.16 + pow(Self.random(pair, salt: 8.13), 0.6) * 0.74
    }

    var size: Double { isDust ? 1.2 + variation * 0.8 : 1.0 + variation * 1.1 }

    // These scalars are shared by every seed at one history time.
    struct Orbit {
        let radius: Double
        let angle: Double

        init(elapsed: Double, gatherElapsed: Double, duration: Double, closingRadius: Double) {
            let progress = min(gatherElapsed / duration, 1)
            radius = closingRadius + (1 - closingRadius) * PairingCelebrationGatherShape(progress: progress).radius
            angle = max(0, elapsed - gatherElapsed) * 2 + duration * integratedSpin(at: progress)
        }

        func position(seed: PairingCelebrationParticleSeed) -> SIMD3<Double> {
            let angle = seed.speed * angle
            let rotated = seed.direction * cos(angle) + seed.axisCrossDirection * sin(angle)
                + seed.axisProjection * (1 - cos(angle))
            return (seed.shellRadius * radius) * rotated
        }
    }

    // Integrate once so every frame preserves tangential speed as the radius falls.
    private static let spinAngles: [Double] = {
        let count = 512
        var angles = [0.0]
        for index in 1...count {
            let progress = (Double(index) - 0.5) / Double(count)
            let radius = max(0.035, PairingCelebrationGatherShape(progress: progress).radius)
            let ramp = PairingCelebrationParticlePlayback.smoothstep(progress / 0.18)
            angles.append(angles[index - 1] + (2 + 6 * ramp) / radius / Double(count))
        }
        return angles
    }()

    private static func integratedSpin(at progress: Double) -> Double {
        let sample = min(max(progress, 0), 1) * Double(spinAngles.count - 1)
        let index = min(Int(sample), spinAngles.count - 2)
        return spinAngles[index] + (spinAngles[index + 1] - spinAngles[index]) * (sample - Double(index))
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
        let distance = points.reduce(0.0) { distance, point in
            max(distance, hypot(point.x - center.x, point.y - center.y))
        }
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
