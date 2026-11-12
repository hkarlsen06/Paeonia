import SwiftUI

/// A peony drawn in code. One drawing covers every stage, from a tight bud at
/// openness 0 to a full flower at 1, so a flower can open while it animates.
nonisolated enum StreakPeony {
    static let size: CGFloat = 30

    enum Palette {
        /// Warm outer petals and pink inner ones.
        case bloom
        /// A muted bud that has not opened yet.
        case bud
    }

    private static let outerPetals = 7
    private static let innerPetals = 6

    static func draw(
        in context: GraphicsContext,
        at center: CGPoint,
        diameter: CGFloat,
        openness: Double,
        palette: Palette,
        opacity: Double = 1
    ) {
        var context = context
        context.opacity = opacity
        // One layer, so a faded flower fades as a whole instead of showing its overlaps.
        context.drawLayer { layer in
            let open = CGFloat(min(max(openness, 0), 1))
            let outerColor: Color = palette == .bloom ? .paeoniaPeonyPetal : .paeoniaAccentPrimary

            if open < 1 {
                let base = CGPoint(x: center.x, y: center.y + diameter * 0.16)
                for angle in [-130.0, -50.0] {
                    layer.fill(
                        leaf(from: base, length: diameter * 0.3, width: diameter * 0.13, angle: .degrees(angle)),
                        with: .color(.paeoniaStem.opacity(1 - open))
                    )
                }
            }

            let outer = PetalRing(
                count: outerPetals, rotation: .degrees(-90),
                distance: diameter * (0.07 + 0.2 * open), radius: diameter * (0.19 + 0.02 * open)
            )
            // Half a petal round from the outer ring, so each inner petal fills a gap.
            let inner = PetalRing(
                count: innerPetals, rotation: .degrees(-60),
                distance: diameter * (0.04 + 0.09 * open), radius: diameter * (0.12 + 0.03 * open)
            )
            drawPetals(outer.petals(around: center), color: outerColor, in: layer)
            drawPetals(inner.petals(around: center), color: .paeoniaAccentPrimary, in: layer)

            if open > 0 {
                layer.fill(circle(center, radius: diameter * 0.08 * open), with: .color(.paeoniaPeonyHeart))
            }
            if open >= 0.99 {
                layer.fill(circle(center, radius: diameter * 0.045), with: .color(.paeoniaInkGold))
            }
        }
    }

    /// A pointed leaf from `base` toward `angle`, also used for the stem's leaves.
    static func leaf(from base: CGPoint, length: CGFloat, width: CGFloat, angle: Angle) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length / 2, y: -width))
        path.addQuadCurve(to: .zero, control: CGPoint(x: length / 2, y: width))
        return path.applying(
            CGAffineTransform(translationX: base.x, y: base.y).rotated(by: angle.radians)
        )
    }

    private struct PetalRing {
        let count: Int
        let rotation: Angle
        let distance: CGFloat
        let radius: CGFloat

        func petals(around center: CGPoint) -> [Path] {
            (0..<count).map { index in
                let angle = rotation.radians + 2 * .pi * Double(index) / Double(count)
                let petalCenter = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
                return circle(petalCenter, radius: radius)
            }
        }
    }

    /// Each petal is filled, then edged a little darker, so the next petal overlaps it cleanly.
    private static func drawPetals(_ petals: [Path], color: Color, in context: GraphicsContext) {
        for petal in petals {
            context.fill(petal, with: .color(color))
            context.stroke(petal, with: .color(.paeoniaBackgroundSecondary.opacity(0.35)), lineWidth: 0.6)
        }
    }

    private static func circle(_ center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
