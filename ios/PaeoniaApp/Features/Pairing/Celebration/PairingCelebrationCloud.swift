import SwiftUI

struct PairingCelebrationCloud {
    private struct Lobe {
        let center: CGPoint
        let depth: Double
        let radius: Double
        let color: Color
    }

    static func draw(in drawingContext: inout GraphicsContext, projection: PairingCelebrationParticleProjection,
                     playback: PairingCelebrationParticlePlayback, time: Double) {
        var context = drawingContext
        let shape = playback.gatherShape(at: time)
        var opacity = shape.cover
        if case let .bursting(_, since, _) = playback.stage {
            opacity *= 1 - PairingCelebrationParticlePlayback.smoothstep((time - since) / 0.12)
        }
        guard opacity > 0 else { return }
        let scale = 1 - shape.compression * (1 - 3.0 / 70)
        let center = projection.center
        let angle = (time - playback.started) * 2.4
        context.opacity = opacity
        lobe(in: &context, center: center, radius: 62 * scale, color: .paeoniaAccentPrimary,
             opaque: true)
        let lobes = (0..<8).map { index -> Lobe in
            let phase = Double(index) * 2.3999632297 + angle
            let depth = sin(phase * 0.83 + Double(index))
            let offset = (26 + 10 * sin(phase * 0.7)) * scale
            let position = CGPoint(x: center.x + cos(phase) * offset,
                                   y: center.y + sin(phase) * offset * 0.78)
            return Lobe(center: position, depth: depth, radius: (38 + depth * 10) * scale,
                        color: index.isMultiple(of: 3) ? .paeoniaPartnerTwo : .paeoniaAccentSecondary)
        }.sorted { $0.depth < $1.depth }
        for lobe in lobes {
            var layer = context
            layer.opacity *= 0.40 + 0.20 * lobe.depth
            self.lobe(in: &layer, center: lobe.center, radius: lobe.radius,
                      color: lobe.color, opaque: false)
        }
        var point = context
        point.opacity *= shape.compression
        lobe(in: &point, center: center, radius: 10, color: .paeoniaTextPrimary, opaque: false)
        lobe(in: &point, center: center, radius: 3, color: .paeoniaTextPrimary, opaque: false)
    }

    private static func lobe(in context: inout GraphicsContext, center: CGPoint, radius: Double,
                             color: Color, opaque: Bool) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let gradient = Gradient(stops: [
            .init(color: color, location: 0),
            .init(color: color.opacity(opaque ? 1 : 0.7), location: 0.40),
            .init(color: color.opacity(opaque ? 1 : 0.3), location: 0.70),
            .init(color: color.opacity(0), location: 1)
        ])
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            gradient, center: center, startRadius: 0, endRadius: radius))
    }
}
