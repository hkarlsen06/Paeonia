import SwiftUI

/// A spark in flight after a move, from the cell just played to the small
/// board that cell sends the next player to.
nonisolated struct UltimateTicTacToeSpark: Equatable {
    /// The move just played, 0..<81.
    let move: Int
    /// The small board the next player must use.
    let target: Int
    let start: Date
}

/// Draws the spark on a canvas the size of the whole board. It travels on a
/// slight arc over `UltimateTicTacToeTiming.spark` with a short fading tail.
/// The playback removes it when it arrives.
struct UltimateTicTacToeSparkView: View {
    let spark: UltimateTicTacToeSpark
    let geometry: UltimateTicTacToeBoardGeometry
    let color: Color

    private static let tailSteps = 9

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(spark.start)
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                draw(in: &context, progress: min(max(elapsed / UltimateTicTacToeTiming.spark, 0), 1))
            }
        }
        .frame(width: geometry.side, height: geometry.side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, progress: Double) {
        let from = geometry.cellRect(board: spark.move / 9, cell: spark.move % 9)
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = geometry.center(of: spark.target)
        // The arc bows to the left of the flight, by a sixth of its length.
        let control = CGPoint(
            x: (start.x + end.x) / 2 + (end.y - start.y) / 6,
            y: (start.y + end.y) / 2 - (end.x - start.x) / 6
        )
        let radius = geometry.smallSide * 0.05
        // In over the first tenth, and a little dimmer as it lands.
        let fade = min(progress / 0.1, 1) * (1 - max(progress - 0.8, 0) * 2)
        let head = Self.eased(progress)

        for step in stride(from: Self.tailSteps, through: 1, by: -1) {
            let share = Double(step) / Double(Self.tailSteps + 1)
            let point = Self.point(at: max(head - Double(step) * 0.035, 0), start, control, end)
            let size = radius * (1 - share)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)),
                with: .color(color.opacity(0.55 * (1 - share) * fade))
            )
        }

        let center = Self.point(at: head, start, control, end)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 1.2))
            let halo = radius * 2.4
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
                with: .color(color.opacity(0.6 * fade))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(color.opacity(fade))
        )
        let core = radius * 0.45
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
            with: .color(.white.opacity(0.9 * fade))
        )
    }

    /// Ease in and out, so the spark leaves gently and slows as it lands.
    private static func eased(_ progress: Double) -> Double {
        progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
    }

    /// A point on the quadratic curve from `start` through `control` to `end`.
    private static func point(at progress: Double, _ start: CGPoint, _ control: CGPoint, _ end: CGPoint) -> CGPoint {
        let rest = 1 - progress
        return CGPoint(
            x: rest * rest * start.x + 2 * rest * progress * control.x + progress * progress * end.x,
            y: rest * rest * start.y + 2 * rest * progress * control.y + progress * progress * end.y
        )
    }
}
