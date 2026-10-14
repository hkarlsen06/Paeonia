import SwiftUI

/// One part of the creature on the hub card, drawn with paths in the widget ink
/// colors: a cat's head, a striped sweater and chicken legs. The lines that cross
/// a fold leave one part at the same x where the next part picks them up.
struct ExquisiteCorpseHubDoodle: View {
    let part: ExquisiteCorpsePartKind
    /// How much of the part is drawn, from 0 to 1. The lines are drawn one after
    /// another in layer order, and a filled shape appears once its turn comes.
    var drawn: Double = 1

    var body: some View {
        Canvas { context, size in
            let layers = Self.layers(for: part, in: size)
            for (index, layer) in layers.enumerated() {
                let share = 1 / Double(layers.count)
                let amount = min(max((drawn - Double(index) * share) / share, 0), 1)
                guard amount > 0 else { continue }
                if layer.isFilled {
                    context.opacity = amount
                    context.fill(layer.path, with: .color(layer.color))
                    context.opacity = 1
                } else {
                    context.stroke(
                        layer.path.trimmedPath(from: 0, to: amount),
                        with: .color(layer.color),
                        style: StrokeStyle(lineWidth: layer.width, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private struct Layer {
        let path: Path
        let color: Color
        var width: CGFloat = 2
        var isFilled = false
    }

    private static func layers(for part: ExquisiteCorpsePartKind, in size: CGSize) -> [Layer] {
        switch part {
        case .head: head(in: size)
        case .body: body(in: size)
        case .legs: legs(in: size)
        }
    }

    /// Maps fractions of the part to a point in it.
    private static func unitPoint(in size: CGSize) -> (CGFloat, CGFloat) -> CGPoint {
        { x, y in CGPoint(x: x * size.width, y: y * size.height) }
    }

    /// The x of each leg, where the sweater's hem lets go of them.
    private static let legX: [CGFloat] = [0.38, 0.62]

    // MARK: Cat's head

    private static func head(in size: CGSize) -> [Layer] {
        let point = unitPoint(in: size)
        let face = Path(ellipseIn: CGRect(
            x: 0.28 * size.width,
            y: 0.18 * size.height,
            width: 0.44 * size.width,
            height: 0.68 * size.height
        ))
        let ears = Path { path in
            path.move(to: point(0.31, 0.34))
            path.addLine(to: point(0.30, 0.04))
            path.addLine(to: point(0.43, 0.20))
            path.move(to: point(0.69, 0.34))
            path.addLine(to: point(0.70, 0.04))
            path.addLine(to: point(0.57, 0.20))
        }
        // The neck leaves the head at the same x as the sweater's collar.
        let neck = Path { path in
            path.move(to: point(0.44, 0.85))
            path.addLine(to: point(0.44, 1))
            path.move(to: point(0.56, 0.85))
            path.addLine(to: point(0.56, 1))
        }
        return [
            Layer(path: face, color: .paeoniaWidgetDrawing),
            Layer(path: ears, color: .paeoniaWidgetDrawing),
            Layer(path: neck, color: .paeoniaWidgetDrawing),
        ] + catFace(in: size)
    }

    private static func catFace(in size: CGSize) -> [Layer] {
        let point = unitPoint(in: size)
        let eyes = Path { path in
            let eyeXs: [CGFloat] = [0.42, 0.58]
            for x in eyeXs {
                let eye = CGRect(x: x * size.width - 2.2, y: 0.46 * size.height - 2.2, width: 4.4, height: 4.4)
                path.addEllipse(in: eye)
            }
        }
        let nose = Path { path in
            path.move(to: point(0.475, 0.55))
            path.addLine(to: point(0.525, 0.55))
            path.addLine(to: point(0.5, 0.62))
            path.closeSubpath()
        }
        let mouth = Path { path in
            path.move(to: point(0.5, 0.62))
            path.addQuadCurve(to: point(0.45, 0.70), control: point(0.49, 0.71))
            path.move(to: point(0.5, 0.62))
            path.addQuadCurve(to: point(0.55, 0.70), control: point(0.51, 0.71))
        }
        let whiskers = Path { path in
            path.move(to: point(0.37, 0.58))
            path.addLine(to: point(0.27, 0.54))
            path.move(to: point(0.37, 0.64))
            path.addLine(to: point(0.27, 0.66))
            path.move(to: point(0.63, 0.58))
            path.addLine(to: point(0.73, 0.54))
            path.move(to: point(0.63, 0.64))
            path.addLine(to: point(0.73, 0.66))
        }
        return [
            Layer(path: mouth, color: .paeoniaWidgetDrawing, width: 1.4),
            Layer(path: whiskers, color: Color.paeoniaInkLavender, width: 1.2),
            Layer(path: eyes, color: Color.paeoniaInkGold, isFilled: true),
            Layer(path: nose, color: .paeoniaAccentSecondary, isFilled: true),
        ]
    }

    // MARK: Striped sweater

    private static func body(in size: CGSize) -> [Layer] {
        let point = unitPoint(in: size)
        let neck = Path { path in
            path.move(to: point(0.44, 0))
            path.addLine(to: point(0.44, 0.12))
            path.move(to: point(0.56, 0))
            path.addLine(to: point(0.56, 0.12))
        }
        let neckline = Path { path in
            path.move(to: point(0.44, 0.12))
            path.addQuadCurve(to: point(0.56, 0.12), control: point(0.5, 0.26))
        }
        let legs = Path { path in
            for x in legX {
                path.move(to: point(x, 0.88))
                path.addLine(to: point(x, 1))
            }
        }
        return [
            Layer(path: neck, color: .paeoniaWidgetDrawing),
            Layer(path: sweater(in: size), color: Color.paeoniaInkBlue),
            Layer(path: neckline, color: Color.paeoniaInkBlue),
            Layer(path: stripe(at: 0.32, in: size), color: Color.paeoniaInkGold),
            Layer(path: stripe(at: 0.52, in: size), color: Color.paeoniaInkLavender),
            Layer(path: stripe(at: 0.70, in: size), color: Color.paeoniaInkGold),
            Layer(path: legs, color: Color.paeoniaInkGold),
        ]
    }

    /// The collar, both sleeves and the hem in one line, left to right.
    private static func sweater(in size: CGSize) -> Path {
        let point = unitPoint(in: size)
        return Path { path in
            path.move(to: point(0.44, 0.12))
            path.addLine(to: point(0.36, 0.17))
            path.addLine(to: point(0.25, 0.22))
            path.addLine(to: point(0.19, 0.78))
            path.addLine(to: point(0.28, 0.80))
            path.addLine(to: point(0.30, 0.42))
            path.addLine(to: point(0.32, 0.88))
            path.addLine(to: point(0.68, 0.88))
            path.addLine(to: point(0.70, 0.42))
            path.addLine(to: point(0.72, 0.80))
            path.addLine(to: point(0.81, 0.78))
            path.addLine(to: point(0.75, 0.22))
            path.addLine(to: point(0.64, 0.17))
            path.addLine(to: point(0.56, 0.12))
        }
    }

    /// One stripe across the sweater at a height. Above the armpit it runs from
    /// sleeve to sleeve. Below it, the sleeves and the body get a stripe each.
    private static func stripe(at y: CGFloat, in size: CGSize) -> Path {
        let point = unitPoint(in: size)
        // Stops a hair inside the outline, so the round line ends stay inside it.
        let inset: CGFloat = 0.008
        let outer = 0.25 - (y - 0.22) * (0.06 / 0.56) + inset
        return Path { path in
            guard y > 0.42 else {
                path.move(to: point(outer, y))
                path.addLine(to: point(1 - outer, y))
                return
            }
            let sleeveInner = 0.30 - (y - 0.42) * (0.02 / 0.38) - inset
            let bodySide = 0.30 + (y - 0.42) * (0.02 / 0.46) + inset
            let segments: [(CGFloat, CGFloat)] = [
                (outer, sleeveInner),
                (bodySide, 1 - bodySide),
                (1 - sleeveInner, 1 - outer),
            ]
            for (start, end) in segments {
                path.move(to: point(start, y))
                path.addLine(to: point(end, y))
            }
        }
    }

    // MARK: Chicken legs

    private static func legs(in size: CGSize) -> [Layer] {
        let point = unitPoint(in: size)
        let legs = Path { path in
            for x in legX {
                path.move(to: point(x, 0))
                path.addLine(to: point(x, 0.62))
                // Three toes that fan out forward.
                let toes: [(CGFloat, CGFloat)] = [(x - 0.08, 0.88), (x, 0.92), (x + 0.08, 0.88)]
                for (toeX, toeY) in toes {
                    path.move(to: point(x, 0.62))
                    path.addLine(to: point(toeX, toeY))
                }
            }
        }
        return [Layer(path: legs, color: Color.paeoniaInkGold)]
    }
}
