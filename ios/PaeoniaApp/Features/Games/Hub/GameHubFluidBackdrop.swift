import SwiftUI

/// A game card's backdrop: a 3 by 3 mesh of the colors from the card's own picture that
/// drifts slowly, like the background behind a song in Apple Music. The bottom row is
/// darker, since the card's text sits there. It stands still with Reduce Motion and while
/// the app is not active, and it crossfades when the palette changes.
struct GameHubFluidBackdrop: View {
    let palette: GameHubPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let isMoving = !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isMoving)) { context in
            let time = isMoving ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                MeshGradient(
                    width: 3, height: 3,
                    points: Self.points(at: time, phase: phase),
                    colors: Self.colors(palette).map(Color.init)
                )
                .id(palette)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: palette)
        .accessibilityHidden(true)
    }

    /// Cards with different pictures drift out of step with each other.
    private var phase: Double {
        Double(palette.colors[0].red + palette.colors[1].green) * 4
    }

    /// The mesh's colors, row by row from the top. Each palette color appears in two or
    /// three places so the backdrop blends them instead of showing four blocks.
    nonisolated static func colors(_ palette: GameHubPalette) -> [Color.Resolved] {
        let color = palette.colors
        return [
            color[0], color[1], color[2],
            color[3], color[0], color[1],
            color[2].dimmed(by: 0.5), color[3].dimmed(by: 0.5), color[0].dimmed(by: 0.5),
        ]
    }

    /// The mesh's points at `time` seconds. The middle point and the middle of each edge
    /// sway by up to 8 percent, each with its own period between 8 and 14 seconds.
    nonisolated static func points(at time: Double, phase: Double) -> [SIMD2<Float>] {
        func sway(_ period: Double, _ offset: Double) -> Float {
            0.5 + 0.08 * Float(sin(time * 2 * .pi / period + phase + offset))
        }
        return [
            [0, 0], [sway(11, 0), 0], [1, 0],
            [0, sway(9, 1)], [sway(13, 2), sway(8, 3)], [1, sway(12, 4)],
            [0, 1], [sway(14, 5), 1], [1, 1],
        ]
    }
}
