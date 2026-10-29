import QuartzCore
import SwiftUI

struct PairingCelebrationParticleField: View {
    let playback: PairingCelebrationParticlePlayback
    let showsParticles: Bool
    private struct Shading {
        let color: Color
        let opacity: Double
        let radius: Double
    }

    private struct Particle {
        let position: SIMD3<Double>
        let isDust: Bool
        let history: [SIMD3<Double>]
        let samples: [CGPoint]
        let shading: Shading
    }

    private static let seeds = (0..<(PairingCelebrationParticleSeed.starCount
        + PairingCelebrationParticleSeed.dustCount)).map { PairingCelebrationParticleSeed(index: $0) }

    var body: some View {
        TimelineView(.animation) { _ in
            let now = CACurrentMediaTime()
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size, time: now)
            } symbols: {
                PairingCelebrationHeartCore().tag(0)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let projection = PairingCelebrationParticleProjection(size: size)
        let shape = playback.gatherShape(at: time)
        let particles = showsParticles ? particles(projection: projection, time: time) : []
        drawParticles(particles, in: &context, foreground: false, shape: shape)
        if let heart = context.resolveSymbol(id: 0) {
            var heartContext = context
            heartContext.opacity = showsParticles ? playback.heartOpacity(at: time) : 1
            let radius = playback.radius(at: time, closingRadius: projection.closingRadius) * projection.radius
            let scale = showsParticles ? min(1, radius / (PairingCelebrationTiming.heartSize * 1.05)) : 1
            heartContext.translateBy(x: projection.center.x, y: projection.center.y)
            heartContext.scaleBy(x: scale, y: scale)
            heartContext.draw(heart, at: .zero)
        }
        drawParticles(particles, in: &context, foreground: true, shape: shape)
    }

    private func particles(projection: PairingCelebrationParticleProjection, time: Double) -> [Particle] {
        let shape = playback.gatherShape(at: time)
        let opacity = playback.opacity(at: time)
        let radius = playback.radius(at: time, closingRadius: projection.closingRadius)
        let markScale = min(1, max(0.08, radius / 0.62))
        let frames = (0...8).map { step in
            PairingCelebrationParticlePlayback.SampleFrame(
                playback: playback, time: time - Double(8 - step) * 0.012 * markScale,
                closingRadius: projection.closingRadius)
        }
        var pairedHistory = [SIMD3<Double>]()
        return Self.seeds.compactMap { seed -> Particle? in
            let density = seed.isDust ? shape.cover : 1
            guard density * opacity > 0.001 else { return nil }
            let segments = seed.isDust ? 5 : 8
            let history: [SIMD3<Double>]
            if seed.index.isMultiple(of: 2) {
                history = playback.history(seed: seed, frames: frames.suffix(segments + 1))
                pairedHistory = history
            } else {
                // Opposite seeds share every motion scalar and keep opposite positions.
                history = pairedHistory.map { -$0 }
            }
            let position = history[segments]
            let depth = min(max((position.z + 1) / 2, 0), 1)
            let growth = 1 + shape.cover * (seed.isDust ? 0 : 0.35)
            let orbRadius = seed.size * (0.86 + 0.28 * depth) * growth * markScale
            // Shorten the sampled trail together with its head during compression.
            let samples = history.map { projection.point($0) }
            let visibility = visibility(projection: projection, samples: samples,
                                        extent: orbRadius * 3.8 + 1, seed: seed, time: time)
            guard visibility > 0 else { return nil }
            let depthOpacity = 0.55 + 0.25 * depth
            let ink = Shading(color: particleColor(seed.index / 2),
                              opacity: opacity * density * visibility
                                * (depthOpacity + (0.99 - depthOpacity) * shape.cover),
                              radius: orbRadius)
            return Particle(position: position, isDust: seed.isDust, history: history, samples: samples, shading: ink)
        }.sorted { $0.position.z < $1.position.z }
    }

    private func drawParticles(_ particles: [Particle], in context: inout GraphicsContext,
                               foreground: Bool, shape: PairingCelebrationGatherShape) {
        for particle in particles {
            if particle.isDust && !foreground { continue }
            drawTrails(in: &context, particle: particle, growth: shape.cover, foreground: foreground)
            guard (particle.isDust || particle.position.z >= 0) == foreground,
                  let point = particle.samples.last else { continue }
            if particle.isDust {
                let radius = particle.shading.radius
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                   width: radius * 2, height: radius * 2)),
                             with: .color(particle.shading.color.opacity(particle.shading.opacity)))
            } else {
                drawHead(in: &context, point: point, shading: particle.shading)
            }
        }
    }

    private func visibility(projection: PairingCelebrationParticleProjection, samples: [CGPoint],
                            extent: Double, seed: PairingCelebrationParticleSeed, time: Double) -> Double {
        if playback.releaseProgress(at: time) != nil {
            return projection.burstVisibility(points: samples, extent: extent, seed: seed)
                * projection.visibility(points: samples, extent: extent)
                * playback.sparkOpacity(seed: seed, at: time)
        }
        return projection.visibility(points: samples, extent: extent)
    }

    private func drawHead(in context: inout GraphicsContext, point: CGPoint,
                          shading: Shading) {
        let color = shading.color
        let depthOpacity = shading.opacity
        let orbRadius = shading.radius
        let rect = CGRect(x: point.x - orbRadius, y: point.y - orbRadius,
                          width: orbRadius * 2, height: orbRadius * 2)
        let glowRadius = orbRadius * 2.6
        let glow = CGRect(x: point.x - glowRadius, y: point.y - glowRadius,
                          width: glowRadius * 2, height: glowRadius * 2)
        context.fill(Path(ellipseIn: glow), with: .radialGradient(
            Gradient(colors: [color.opacity(depthOpacity * 0.20), .clear]),
            center: point, startRadius: 0, endRadius: glowRadius))
        let highlight = CGPoint(x: point.x - orbRadius * 0.32, y: point.y - orbRadius * 0.38)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: .paeoniaTextPrimary.opacity(depthOpacity * 0.65), location: 0),
                .init(color: color.opacity(depthOpacity), location: 0.38),
                .init(color: .paeoniaBackgroundPrimary.opacity(depthOpacity), location: 1)
            ]), center: highlight, startRadius: 0, endRadius: orbRadius * 1.6))
    }

    private func drawTrails(in context: inout GraphicsContext, particle: Particle,
                            growth: Double, foreground: Bool) {
        let history = particle.history
        let samples = particle.samples
        let shading = particle.shading
        var length = 0.0
        let segments = samples.count - 1
        for step in stride(from: segments - 1, through: 0, by: -1) {
            let start = samples[step]
            let end = samples[step + 1]
            length += hypot(end.x - start.x, end.y - start.y)
            guard length <= 35 else { break }
            let startZ = particle.isDust ? 1 : history[step].z
            let endZ = particle.isDust ? 1 : history[step + 1].z
            let tail = Double(step + 1) / Double(segments)
            let trailOpacity = particle.isDust ? (0.35 + 0.60 * tail) : (0.14 + 0.34 * growth) * tail
            let ink = Shading(color: shading.color, opacity: shading.opacity * trailOpacity,
                              radius: shading.radius * (particle.isDust ? 1.65 : 1))
            if (startZ >= 0) != (endZ >= 0) {
                let split = startZ / (startZ - endZ)
                let crossing = CGPoint(x: start.x + (end.x - start.x) * split,
                                       y: start.y + (end.y - start.y) * split)
                if (startZ >= 0) == foreground {
                    stroke(in: &context, from: start, to: crossing, shading: ink)
                }
                if (endZ >= 0) == foreground {
                    stroke(in: &context, from: crossing, to: end, shading: ink)
                }
            } else if (startZ >= 0) == foreground {
                stroke(in: &context, from: start, to: end, shading: ink)
            }
        }
    }

    private func stroke(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint,
                        shading: Shading) {
        var trail = Path()
        trail.move(to: start)
        trail.addLine(to: end)
        context.stroke(trail, with: .color(shading.color.opacity(shading.opacity)),
                       style: StrokeStyle(lineWidth: shading.radius * 0.65, lineCap: .round))
    }

    private func particleColor(_ index: Int) -> Color {
        switch index % 4 {
        case 0: .paeoniaAccentPrimary
        case 1: .paeoniaAccentSecondary
        case 2: .paeoniaPartnerTwo
        default: .paeoniaTextPrimary
        }
    }
}
