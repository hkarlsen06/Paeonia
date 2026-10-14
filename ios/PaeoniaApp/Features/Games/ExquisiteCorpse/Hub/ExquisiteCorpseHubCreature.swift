import SwiftUI

/// The creature on the hub card, drawn as one picture across the three parts of the
/// strip: a lavender kitten's head, a cozy sweater with a heart, and duck feet. The
/// raised paw, the neck and the legs cross the folds, as they do in a real game.
struct ExquisiteCorpseHubCreature: View {
    /// The size the drawing is laid out in. It scales to fill its frame.
    static let size = CGSize(width: 132, height: 144)

    /// How shut the eyes are, from 0 (open) to 1 (shut).
    var blink: Double = 0
    /// How far the raised arm swings from where it rests, in degrees.
    var wave: Double = 0

    private static let ink = Color.paeoniaTextInverse
    private static let lineWidth: CGFloat = 2.2

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / Self.size.width, y: size.height / Self.size.height)
            // Room above the ears, so they clear the top of the paper.
            context.translateBy(x: 0, y: 4)
            drawLegs(in: context)
            drawArms(in: context)
            drawSweater(in: context)
            drawHead(in: context)
        }
        .accessibilityHidden(true)
    }

    /// Fills a shape and outlines it in ink, like a sticker.
    private func paint(_ path: Path, _ color: Color, in context: GraphicsContext) {
        context.fill(path, with: .color(color))
        context.stroke(
            path,
            with: .color(Self.ink),
            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: Duck feet

    private func drawLegs(in context: GraphicsContext) {
        // Each foot turns out a little from its leg.
        let legs: [(leg: CGFloat, foot: CGFloat)] = [(56, 51), (76, 81)]
        for (legX, footX) in legs {
            let leg = Path { path in
                path.move(to: CGPoint(x: legX, y: 96))
                path.addLine(to: CGPoint(x: legX, y: 118))
            }
            context.stroke(leg, with: .color(Self.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            paint(Self.foot(from: CGPoint(x: legX, y: 115), centeredAt: footX), .paeoniaInkGold, in: context)
        }
    }

    /// A webbed foot that fans out from the bottom of a leg, with three round toes.
    private static func foot(from ankle: CGPoint, centeredAt x: CGFloat) -> Path {
        let toeY = ankle.y + 13
        return Path { path in
            path.move(to: ankle)
            path.addLine(to: CGPoint(x: x - 12, y: toeY))
            for toe in 0..<3 {
                let left = x - 12 + CGFloat(toe) * 8
                path.addQuadCurve(to: CGPoint(x: left + 8, y: toeY), control: CGPoint(x: left + 4, y: toeY + 6))
            }
            path.closeSubpath()
        }
    }

    // MARK: Sweater

    /// One arm hangs down and the other waves. The sweater covers the shoulders.
    private func drawArms(in context: GraphicsContext) {
        let arms: [(shoulder: CGPoint, degrees: Double)] = [
            (CGPoint(x: 46, y: 58), 130),
            (CGPoint(x: 86, y: 56), -40 + wave),
        ]
        for arm in arms {
            let radians = arm.degrees * .pi / 180
            let paw = CGPoint(x: arm.shoulder.x + 24 * cos(radians), y: arm.shoulder.y + 24 * sin(radians))
            let sleeve = Path { path in
                path.move(to: arm.shoulder)
                path.addLine(to: paw)
            }
            context.stroke(sleeve, with: .color(Self.ink), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            context.stroke(sleeve, with: .color(.paeoniaInkBlue), style: StrokeStyle(lineWidth: 6.6, lineCap: .round))
            let pawShape = Path(ellipseIn: CGRect(x: paw.x - 5.5, y: paw.y - 5.5, width: 11, height: 11))
            paint(pawShape, .paeoniaAccentPrimary, in: context)
        }
    }

    private func drawSweater(in context: GraphicsContext) {
        let frame = CGRect(x: 40, y: 42, width: 52, height: 58)
        let sweater = Path(roundedRect: frame, cornerRadius: 22, style: .continuous)
        context.fill(sweater, with: .color(.paeoniaInkBlue))

        var inside = context
        inside.clip(to: sweater)
        let hemTop: CGFloat = 90
        inside.fill(
            Path(CGRect(x: frame.minX, y: hemTop, width: frame.width, height: frame.maxY - hemTop)),
            with: .color(.paeoniaInkGold)
        )
        let hemLine = Path { path in
            path.move(to: CGPoint(x: frame.minX, y: hemTop))
            path.addLine(to: CGPoint(x: frame.maxX, y: hemTop))
        }
        inside.stroke(hemLine, with: .color(Self.ink), lineWidth: 1.6)
        inside.fill(Self.heart(in: CGRect(x: 58, y: 62, width: 16, height: 14)), with: .color(.paeoniaAccentSecondary))

        context.stroke(sweater, with: .color(Self.ink), lineWidth: Self.lineWidth)
    }

    private static func heart(in rect: CGRect) -> Path {
        let point = { (x: CGFloat, y: CGFloat) in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        return Path { path in
            path.move(to: point(0.5, 0.96))
            path.addCurve(to: point(0, 0.34), control1: point(0.16, 0.74), control2: point(0, 0.56))
            path.addCurve(to: point(0.5, 0.18), control1: point(0, 0.02), control2: point(0.4, -0.04))
            path.addCurve(to: point(1, 0.34), control1: point(0.6, -0.04), control2: point(1, 0.02))
            path.addCurve(to: point(0.5, 0.96), control1: point(1, 0.56), control2: point(0.84, 0.74))
        }
    }

    // MARK: Kitten's head

    private func drawHead(in context: GraphicsContext) {
        drawEars(in: context)
        paint(Path(ellipseIn: CGRect(x: 34, y: 8, width: 64, height: 42)), .paeoniaInkLavender, in: context)
        drawFace(in: context)
    }

    private func drawEars(in context: GraphicsContext) {
        let centerX = Self.size.width / 2
        for side: CGFloat in [-1, 1] {
            let point = { (x: CGFloat, y: CGFloat) in CGPoint(x: centerX + side * x, y: y) }
            let ear = Path { path in
                path.move(to: point(-27, 20))
                path.addLine(to: point(-25, 1))
                path.addLine(to: point(-6, 10))
                path.closeSubpath()
            }
            let innerEar = Path { path in
                path.move(to: point(-23, 15))
                path.addLine(to: point(-22, 6))
                path.addLine(to: point(-12, 11))
                path.closeSubpath()
            }
            paint(ear, .paeoniaInkLavender, in: context)
            context.fill(innerEar, with: .color(.paeoniaAccentPrimary))
        }
    }

    private func drawFace(in context: GraphicsContext) {
        let centerX = Self.size.width / 2
        for side: CGFloat in [-1, 1] {
            let cheek = CGRect(x: centerX + side * 19 - 5, y: 34, width: 10, height: 6)
            context.fill(Path(ellipseIn: cheek), with: .color(.paeoniaAccentSecondary.opacity(0.6)))

            let eyeHeight = 9 * (1 - 0.85 * blink)
            let eyeX = centerX + side * 11
            context.fill(
                Path(ellipseIn: CGRect(x: eyeX - 3.5, y: 29 - eyeHeight / 2, width: 7, height: eyeHeight)),
                with: .color(Self.ink)
            )
            if blink < 0.5 {
                let shine = CGRect(x: eyeX - 2.4, y: 25.6, width: 2.8, height: 2.8)
                context.fill(Path(ellipseIn: shine), with: .color(.paeoniaWidgetDrawing))
            }
        }

        let nose = Path { path in
            path.move(to: CGPoint(x: centerX - 2, y: 32.5))
            path.addLine(to: CGPoint(x: centerX + 2, y: 32.5))
            path.addLine(to: CGPoint(x: centerX, y: 35))
            path.closeSubpath()
        }
        context.fill(nose, with: .color(.paeoniaAccentSecondary))
        let mouth = Path { path in
            path.move(to: CGPoint(x: centerX - 4, y: 36))
            path.addQuadCurve(to: CGPoint(x: centerX, y: 36), control: CGPoint(x: centerX - 2, y: 39.5))
            path.addQuadCurve(to: CGPoint(x: centerX + 4, y: 36), control: CGPoint(x: centerX + 2, y: 39.5))
        }
        context.stroke(mouth, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}
