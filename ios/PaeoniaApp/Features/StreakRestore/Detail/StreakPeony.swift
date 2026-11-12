import SwiftUI

/// A peony drawn in code. One drawing covers every stage, from a tight bud at
/// openness 0 to a full flower at 1, so a flower can open while it animates.
nonisolated enum StreakPeony {
    static let size: CGFloat = 38

    enum Palette {
        /// Warm outer petals and pink inner ones.
        case bloom
        /// A muted bud that has not opened yet.
        case bud
    }

    private static let outerPetals = 8
    private static let middlePetals = 6
    private static let innerPetals = 5

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
        let open = CGFloat(min(max(openness, 0), 1))
        // One layer, so a faded flower fades as a whole instead of showing its overlaps.
        context.drawLayer { layer in
            if open < 1 {
                drawSepals(in: layer, at: center, diameter: diameter, opacity: 1 - open)
            }
            if palette == .bloom, open > 0.5 {
                drawGlow(in: layer, at: center, diameter: diameter, open: open)
            }
            drawRings(in: layer, at: center, diameter: diameter, open: open, palette: palette)
            if open >= 0.99 {
                layer.fill(circle(center, radius: diameter * 0.07), with: .color(.paeoniaInkGold))
            }
        }
    }

    private static func drawSepals(
        in context: GraphicsContext, at center: CGPoint, diameter: CGFloat, opacity: Double
    ) {
        let base = CGPoint(x: center.x, y: center.y + diameter * 0.16)
        for angle in [-130.0, -50.0] {
            context.fill(
                leaf(from: base, length: diameter * 0.3, width: diameter * 0.13, angle: .degrees(angle)),
                with: .color(.paeoniaStem.opacity(opacity))
            )
        }
    }

    private static func drawGlow(in context: GraphicsContext, at center: CGPoint, diameter: CGFloat, open: CGFloat) {
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: diameter * 0.14))
            glow.fill(
                circle(center, radius: diameter * 0.42 * open),
                with: .color(.paeoniaAccentPrimary.opacity(0.45 * Double(open)))
            )
        }
    }

    private static func drawRings(
        in context: GraphicsContext, at center: CGPoint, diameter: CGFloat, open: CGFloat, palette: Palette
    ) {
        let outerColor: Color = palette == .bloom ? .paeoniaPeonyPetal : .paeoniaAccentPrimary
        let outer = PetalRing(
            count: outerPetals, rotation: .degrees(-90),
            distance: diameter * (0.07 + 0.22 * open), radius: diameter * (0.18 + 0.02 * open)
        )
        // Each ring sits half a petal round from the one outside it, so its petals fill the gaps.
        let middle = PetalRing(
            count: middlePetals, rotation: .degrees(-60),
            distance: diameter * (0.05 + 0.12 * open), radius: diameter * (0.13 + 0.04 * open)
        )
        let inner = PetalRing(
            count: innerPetals, rotation: .degrees(-90),
            distance: diameter * (0.02 + 0.05 * open), radius: diameter * (0.09 + 0.03 * open)
        )
        let shade = PetalShade(center: center, radius: diameter / 2)
        drawPetals(outer.petals(around: center), shade: shade.outer(outerColor), in: context)
        drawPetals(middle.petals(around: center), shade: shade.inner(.paeoniaAccentPrimary), in: context)
        let heart: Color = palette == .bloom ? .paeoniaPeonyHeart : .paeoniaAccentPrimary
        drawPetals(inner.petals(around: center), shade: shade.inner(heart), in: context)
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

    /// Petals are darker toward the flower's centre and lighter at their tips, which gives the
    /// flat shapes some depth.
    private struct PetalShade {
        let center: CGPoint
        let radius: CGFloat

        func outer(_ color: Color) -> GraphicsContext.Shading {
            shading([color.mix(with: .paeoniaBackgroundSecondary, by: 0.35), color, color.mix(with: .white, by: 0.2)])
        }

        func inner(_ color: Color) -> GraphicsContext.Shading {
            shading([color.mix(with: .paeoniaPeonyPetal, by: 0.5), color, color.mix(with: .white, by: 0.25)])
        }

        private func shading(_ colors: [Color]) -> GraphicsContext.Shading {
            .radialGradient(Gradient(colors: colors), center: center, startRadius: 0, endRadius: radius)
        }
    }

    /// Each petal is filled, then edged a little darker, so the next petal overlaps it cleanly.
    private static func drawPetals(_ petals: [Path], shade: GraphicsContext.Shading, in context: GraphicsContext) {
        for petal in petals {
            context.fill(petal, with: shade)
            context.stroke(petal, with: .color(.paeoniaBackgroundSecondary.opacity(0.3)), lineWidth: 0.6)
        }
    }

    private static func circle(_ center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
