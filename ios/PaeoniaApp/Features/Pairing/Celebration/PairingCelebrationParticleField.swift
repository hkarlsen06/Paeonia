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
        let projection = PairingCelebrationParticleProjection(size: size)
        let particles = Self.seeds.map { ($0, playback.position(seed: $0, at: time)) }
            .sorted { $0.1.z < $1.1.z }
        for (seed, position) in particles where (position.z >= 0) == foreground {
            let perspective = projection.perspective(position)
            let point = projection.point(position)
            let orbRadius = seed.size * perspective
            let color = particleColor(seed.index)
            let samples = (0...8).map { step in
                projection.point(playback.position(seed: seed, at: time - Double(8 - step) * 0.006))
            }
            let visibility = projection.visibility(points: samples, extent: orbRadius * 2 + 1)
            guard visibility > 0 else { continue }
            let depth = min(max((position.z + 1) / 2, 0), 1)
            let depthOpacity = opacity * visibility * (0.28 + 0.55 * depth)
            var trail = Path()
            for (step, sample) in samples.enumerated() {
                if step == 0 { trail.move(to: sample) } else { trail.addLine(to: sample) }
            }
            context.stroke(trail, with: .linearGradient(
                Gradient(colors: [.clear, color.opacity(depthOpacity * 0.22)]),
                startPoint: samples[0],
                endPoint: point
            ), style: StrokeStyle(lineWidth: orbRadius * 0.65, lineCap: .round, lineJoin: .round))
            let rect = CGRect(x: point.x - orbRadius, y: point.y - orbRadius,
                              width: orbRadius * 2, height: orbRadius * 2)
            let glow = rect.insetBy(dx: -orbRadius, dy: -orbRadius)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [color.opacity(depthOpacity * 0.12), .clear]),
                center: point, startRadius: 0, endRadius: orbRadius * 2))
            let highlight = CGPoint(x: point.x - orbRadius * 0.32, y: point.y - orbRadius * 0.38)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [
                    .init(color: .paeoniaTextPrimary.opacity(depthOpacity * 0.65), location: 0),
                    .init(color: color.opacity(depthOpacity), location: 0.38),
                    .init(color: .paeoniaBackgroundPrimary.opacity(depthOpacity), location: 1)
                ]), center: highlight, startRadius: 0, endRadius: orbRadius * 1.6))
        }
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
