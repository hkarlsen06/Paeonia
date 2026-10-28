import QuartzCore
import SwiftUI

struct PairingCelebrationParticleField: View {
    let playback: PairingCelebrationParticlePlayback
    let foreground: Bool
    private static let seeds = (0..<120).map { PairingCelebrationParticleSeed(index: $0) }

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
        let center = CGPoint(x: size.width / 2, y: size.height * PairingCelebrationTiming.centerYRatio)
        let radius = min(size.width, size.height) * 0.56
        let particles = Self.seeds.map { ($0, playback.position(seed: $0, at: time)) }
            .sorted { $0.1.z < $1.1.z }
        for (seed, position) in particles where (position.z >= 0) == foreground {
            let perspective = 1 / (1 - position.z * 0.42)
            let point = project(position, center: center, radius: radius)
            let orbRadius = seed.size * perspective
            let color = particleColor(seed.index)
            let depthOpacity = opacity * (0.48 + 0.52 * min(perspective / 1.35, 1))
            var trail = Path()
            for step in 0...8 {
                let earlier = time - Double(8 - step) * 0.006
                let sample = project(playback.position(seed: seed, at: earlier), center: center, radius: radius)
                if step == 0 { trail.move(to: sample) } else { trail.addLine(to: sample) }
            }
            context.stroke(trail, with: .linearGradient(
                Gradient(colors: [.clear, color.opacity(depthOpacity * 0.38)]),
                startPoint: project(playback.position(seed: seed, at: time - 0.048), center: center, radius: radius),
                endPoint: point
            ), style: StrokeStyle(lineWidth: orbRadius * 0.65, lineCap: .round, lineJoin: .round))
            let glow = CGRect(x: point.x - orbRadius * 2, y: point.y - orbRadius * 2,
                              width: orbRadius * 4, height: orbRadius * 4)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [color.opacity(depthOpacity * 0.2), .clear]),
                center: point, startRadius: 0, endRadius: orbRadius * 2))
            let rect = CGRect(x: point.x - orbRadius, y: point.y - orbRadius,
                              width: orbRadius * 2, height: orbRadius * 2)
            let highlight = CGPoint(x: point.x - orbRadius * 0.32, y: point.y - orbRadius * 0.38)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [
                    .init(color: .paeoniaTextPrimary.opacity(depthOpacity), location: 0),
                    .init(color: color.opacity(depthOpacity), location: 0.38),
                    .init(color: .paeoniaBackgroundPrimary.opacity(depthOpacity), location: 1)
                ]), center: highlight, startRadius: 0, endRadius: orbRadius * 1.6))
        }
    }

    private func project(_ position: SIMD3<Double>, center: CGPoint, radius: Double) -> CGPoint {
        let scale = radius / (1 - position.z * 0.42)
        return CGPoint(x: center.x + position.x * scale, y: center.y + position.y * scale)
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
