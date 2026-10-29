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
        let history: [SIMD3<Double>]
        let samples: [CGPoint]
        let shading: Shading
    }

    private static let seeds = (0..<640).map { PairingCelebrationParticleSeed(index: $0) }

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
            heartContext.draw(heart, at: projection.center)
        }
        drawParticles(particles, in: &context, foreground: true, shape: shape)
    }

    private func particles(projection: PairingCelebrationParticleProjection, time: Double) -> [Particle] {
        let shape = playback.gatherShape(at: time)
        let opacity = playback.opacity(at: time)
        var markScale = 1 - 0.94 * shape.compression
        if case let .bursting(_, since, duration) = playback.stage, time >= since {
            markScale += 0.94 * PairingCelebrationParticlePlayback.smoothstep(
                (time - since) / max(0.001, duration * 0.16))
        }
        return Self.seeds.compactMap { seed -> Particle? in
            let density = seed.isDust ? shape.cover : 1
            guard density * opacity > 0.001 else { return nil }
            let position = playback.position(seed: seed, at: time, closingRadius: projection.closingRadius)
            let depth = min(max((position.z + 1) / 2, 0), 1)
            let orbRadius = seed.size * (0.86 + 0.28 * depth) * markScale
            // Shorten the sampled trail together with its head during compression.
            let history = (0...8).map { step in
                playback.position(seed: seed, at: time - Double(8 - step) * 0.012 * markScale,
                                  closingRadius: projection.closingRadius)
            }
            let samples = history.map { projection.point($0) }
            let visibility = visibility(projection: projection, samples: samples,
                                        extent: orbRadius * 3.8 + 1, seed: seed, time: time)
            guard visibility > 0 else { return nil }
            let ink = Shading(color: particleColor(seed.index / 2),
                              opacity: opacity * density * visibility * (0.55 + 0.25 * depth),
                              radius: orbRadius)
            return Particle(position: position, history: history, samples: samples, shading: ink)
        }.sorted { $0.position.z < $1.position.z }
    }

    private func drawParticles(_ particles: [Particle], in context: inout GraphicsContext,
                               foreground: Bool, shape: PairingCelebrationGatherShape) {
        for particle in particles {
            drawTrails(in: &context, particle: particle, growth: shape.cover, foreground: foreground)
            guard (particle.position.z >= 0) == foreground,
                  let point = particle.samples.last else { continue }
            drawHead(in: &context, point: point, shading: particle.shading, envelopment: shape.cover)
        }
    }

    private func visibility(projection: PairingCelebrationParticleProjection, samples: [CGPoint],
                            extent: Double, seed: PairingCelebrationParticleSeed, time: Double) -> Double {
        if case let .bursting(_, since, _) = playback.stage, time >= since {
            return projection.burstVisibility(points: samples, extent: extent, seed: seed)
                * projection.visibility(points: samples, extent: extent)
                * playback.sparkOpacity(seed: seed, at: time)
        }
        return projection.visibility(points: samples, extent: extent)
    }

    private func drawHead(in context: inout GraphicsContext, point: CGPoint,
                          shading: Shading, envelopment: Double) {
        let color = shading.color
        let depthOpacity = shading.opacity
        let orbRadius = shading.radius
        let rect = CGRect(x: point.x - orbRadius, y: point.y - orbRadius,
                          width: orbRadius * 2, height: orbRadius * 2)
        let glowRadius = orbRadius * (2.6 + 1.2 * envelopment)
        let glow = CGRect(x: point.x - glowRadius, y: point.y - glowRadius,
                          width: glowRadius * 2, height: glowRadius * 2)
        context.fill(Path(ellipseIn: glow), with: .radialGradient(
            Gradient(colors: [color.opacity(depthOpacity * (0.16 + 0.40 * envelopment)), .clear]),
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
        for step in stride(from: 7, through: 0, by: -1) {
            let start = samples[step]
            let end = samples[step + 1]
            length += hypot(end.x - start.x, end.y - start.y)
            guard length <= 35 else { break }
            let startZ = history[step].z
            let endZ = history[step + 1].z
            let ink = Shading(color: shading.color,
                              opacity: shading.opacity * (0.14 + 0.34 * growth) * Double(step + 1) / 8,
                              radius: shading.radius)
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
