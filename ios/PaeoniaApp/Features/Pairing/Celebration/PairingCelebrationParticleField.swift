import QuartzCore
import SwiftUI

struct PairingCelebrationParticleField: View {
    let playback: PairingCelebrationParticlePlayback
    let foreground: Bool
    private struct Shading {
        let color: Color
        let opacity: Double
        let radius: Double
    }

    private static let seeds = (0..<240).map { PairingCelebrationParticleSeed(index: $0) }

    var body: some View {
        TimelineView(.animation) { _ in
            let now = CACurrentMediaTime()
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                draw(in: &context, size: size, time: now)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let opacity = playback.opacity(at: time)
        guard opacity > 0 else { return }
        let projection = PairingCelebrationParticleProjection(size: size)
        let growth = playback.gatherProgress(at: time)
        let envelopment = playback.gatherShape(at: time).cover
        if foreground {
            PairingCelebrationCloud.draw(in: &context, projection: projection, playback: playback, time: time)
        }
        let particles = Self.seeds.map {
            ($0, playback.position(seed: $0, at: time, closingRadius: projection.closingRadius))
        }
            .sorted { $0.1.z < $1.1.z }
        for (seed, position) in particles {
            let perspective = projection.perspective(position)
            let point = projection.point(position)
            let orbRadius = seed.size * perspective
            let color = particleColor(seed.index)
            let history = (0...10).map { step in
                playback.position(seed: seed, at: time - Double(10 - step) * 0.011,
                                  closingRadius: projection.closingRadius)
            }
            let samples = history.map { projection.point($0) }
            let visibility = visibility(projection: projection, samples: samples,
                                        extent: orbRadius * 2.6 + 1, seed: seed, time: time)
            guard visibility > 0 else { continue }
            let depth = min(max((position.z + 1) / 2, 0), 1)
            let depthOpacity = opacity * visibility * (0.25 + 0.55 * depth) * (1 + 0.20 * envelopment)
            drawTrails(in: &context, history: history, samples: samples,
                       shading: Shading(color: color, opacity: depthOpacity, radius: orbRadius),
                       growth: growth)
            guard (position.z >= 0) == foreground else { continue }
            drawHead(in: &context, point: point,
                     shading: Shading(color: color, opacity: depthOpacity, radius: orbRadius),
                     envelopment: envelopment)
        }
    }

    private func visibility(projection: PairingCelebrationParticleProjection, samples: [CGPoint],
                            extent: Double, seed: PairingCelebrationParticleSeed, time: Double) -> Double {
        if case let .bursting(_, since, _) = playback.stage, time >= since {
            return projection.burstVisibility(points: samples, extent: extent, seed: seed)
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
        let glowRadius = orbRadius * 2.6
        let glow = CGRect(x: point.x - glowRadius, y: point.y - glowRadius,
                          width: glowRadius * 2, height: glowRadius * 2)
        context.fill(Path(ellipseIn: glow), with: .radialGradient(
            Gradient(colors: [color.opacity(depthOpacity * (0.16 + 0.18 * envelopment)), .clear]),
            center: point, startRadius: 0, endRadius: glowRadius))
        let highlight = CGPoint(x: point.x - orbRadius * 0.32, y: point.y - orbRadius * 0.38)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: .paeoniaTextPrimary.opacity(depthOpacity * 0.65), location: 0),
                .init(color: color.opacity(depthOpacity), location: 0.38),
                .init(color: .paeoniaBackgroundPrimary.opacity(depthOpacity), location: 1)
            ]), center: highlight, startRadius: 0, endRadius: orbRadius * 1.6))
    }

    private func drawTrails(in context: inout GraphicsContext, history: [SIMD3<Double>], samples: [CGPoint],
                            shading: Shading, growth: Double) {
        var length = 0.0
        for step in stride(from: 9, through: 0, by: -1) {
            let start = samples[step]
            let end = samples[step + 1]
            length += hypot(end.x - start.x, end.y - start.y)
            guard length <= 35 else { break }
            let startZ = history[step].z
            let endZ = history[step + 1].z
            let ink = Shading(color: shading.color,
                              opacity: shading.opacity * (0.12 + 0.10 * growth) * Double(step + 1) / 10,
                              radius: shading.radius)
            if (startZ >= 0) != (endZ >= 0) {
                let split = startZ / (startZ - endZ)
                let crossing = CGPoint(x: start.x + (end.x - start.x) * split,
                                       y: start.y + (end.y - start.y) * split)
                stroke(in: &context, from: start, to: crossing, isFront: startZ >= 0,
                       shading: ink)
                stroke(in: &context, from: crossing, to: end, isFront: endZ >= 0,
                       shading: ink)
            } else {
                stroke(in: &context, from: start, to: end, isFront: startZ >= 0,
                       shading: ink)
            }
        }
    }

    private func stroke(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint,
                        isFront: Bool, shading: Shading) {
        guard isFront == foreground else { return }
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
