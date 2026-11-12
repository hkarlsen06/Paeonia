import SwiftUI

/// The vine, its leaves, the growing tip, the flowers and the record mark, drawn in
/// one canvas as tall as a flower. Animatable, so the vine grows and each flower
/// opens as the tip passes it.
struct StreakStemDrawing: View, Animatable {
    let stem: StreakStem
    /// How far the vine has grown toward `stem.growth`, 0 to 1.
    var grown: Double

    var animatableData: Double {
        get { grown }
        set { grown = newValue }
    }

    var body: some View {
        Canvas { context, size in
            StemPainter(stem: stem, tip: stem.growth * grown, size: size).paint(in: context)
        }
    }
}

private nonisolated struct StemPainter {
    let stem: StreakStem
    /// Where the growing tip is now, in the stem's positions.
    let tip: Double
    let size: CGSize

    private static let amplitude: CGFloat = 3
    private static let line = StrokeStyle(lineWidth: 2.5, lineCap: .round)
    /// How far before a flower, as a share of the stem, the tip starts opening it.
    private static let openingRamp = 0.06
    private static let leafCount = 3
    private static let recordRadius: CGFloat = 5

    private var columns: Int { stem.nodes.count }
    private var columnWidth: CGFloat { size.width / CGFloat(columns) }

    func paint(in context: GraphicsContext) {
        context.stroke(vine(to: 1), with: .color(.paeoniaBorder), style: Self.line)
        if tip > 0 {
            context.stroke(vine(to: tip), with: .color(.paeoniaStem), style: Self.line)
            paintLeaves(in: context)
            paintTip(in: context)
        }
        paintFlowers(in: context)
        paintRecord(in: context)
    }

    /// One wave per column, so every flower sits where the wave crosses the middle.
    private func point(_ position: Double) -> CGPoint {
        let x = size.width * position
        return CGPoint(x: x, y: size.height / 2 + Self.amplitude * sin(2 * .pi * x / columnWidth))
    }

    private func vine(to end: Double) -> Path {
        var path = Path()
        path.move(to: point(0))
        var x: CGFloat = 2
        while x < size.width * end {
            path.addLine(to: point(Double(x / size.width)))
            x += 2
        }
        path.addLine(to: point(end))
        return path
    }

    /// Leaves sit between flowers on the newest part of the live vine, and unfold as the tip passes.
    private func paintLeaves(in context: GraphicsContext) {
        let boundaries = (1..<columns).filter { Double($0) / Double(columns) < tip }.suffix(Self.leafCount)
        for boundary in boundaries {
            let position = Double(boundary) / Double(columns)
            let grownIn = min(max((tip - position) * size.width / 12, 0), 1)
            let side: Double = boundary.isMultiple(of: 2) ? 1 : -1
            let leaf = StreakPeony.leaf(
                from: point(position), length: 8 * grownIn, width: 3.5 * grownIn, angle: .degrees(50 * side)
            )
            context.fill(leaf, with: .color(.paeoniaStem))
        }
    }

    private func paintTip(in context: GraphicsContext) {
        let center = point(tip)
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 3))
            glow.fill(Self.circle(center, radius: 5), with: .color(.paeoniaAccentPrimary.opacity(0.6)))
        }
        context.fill(Self.circle(center, radius: 2.5), with: .color(.paeoniaAccentPrimary))
    }

    private func paintFlowers(in context: GraphicsContext) {
        let diameter = min(StreakPeony.size, columnWidth - 4)
        for (index, node) in stem.nodes.enumerated() {
            let position = (Double(index) + 0.5) / Double(columns)
            // A flower past the current streak opens when the tip stops short of it.
            let arrival = min(position, stem.growth)
            let reveal = min(max((tip - arrival) / Self.openingRamp + 1, 0), 1)
            let center = point(position)
            switch node.state {
            case .bloomed:
                StreakPeony.draw(in: context, at: center, diameter: diameter, openness: reveal, palette: .bloom)
            case .opening(let progress):
                StreakPeony.draw(
                    in: context, at: center, diameter: diameter,
                    openness: (0.2 + 0.6 * progress) * reveal, palette: .bloom
                )
            case .bloomedBefore:
                StreakPeony.draw(
                    in: context, at: center, diameter: diameter, openness: 1, palette: .bloom, opacity: 0.35
                )
            case .bud:
                StreakPeony.draw(
                    in: context, at: center, diameter: diameter, openness: 0, palette: .bud, opacity: 0.45
                )
            }
        }
    }

    private func paintRecord(in context: GraphicsContext) {
        guard let record = stem.record else { return }
        let inset = Double(Self.recordRadius / size.width)
        context.stroke(
            Self.circle(point(min(max(record.position, inset), 1 - inset)), radius: Self.recordRadius),
            with: .color(.paeoniaTextSecondary),
            style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])
        )
    }

    private static func circle(_ center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
