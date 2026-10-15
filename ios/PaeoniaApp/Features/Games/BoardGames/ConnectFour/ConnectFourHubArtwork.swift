import SwiftUI

/// The Connect Four card's scene: a cream board full of both partners' discs, three pink
/// discs in a row at the bottom and the fifth column still empty. The beat drops the last
/// pink disc down that column, and the row lights up gold. It follows
/// `docs/games/hub-artwork.md`.
struct ConnectFourHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.6) { progress in
            ConnectFourHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. Spots on the board are fractions of `GameHubConnectFourBoard`.
/// The disc falls behind the board's face, so it only shows through the empty column's
/// holes, and bounces twice in the bottom one. Then the row glows.
private struct ConnectFourHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let board = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 530, aspect: 1.216)
    /// The empty column's holes, top to bottom.
    private static let holes = [0.111, 0.261, 0.409, 0.558, 0.706, 0.854].map { board.point(0.630, $0) }
    private static let holeSize = board.width * 0.107
    /// The middle of the winning row, from the first pink disc to the bottom hole.
    private static let row = board.point(0.430, 0.854)
    private static let rowLength = board.width * 0.4 + holeSize

    var body: some View {
        let glow = Timing.ease(progress, from: 0.62, to: 0.9)
        ZStack {
            GameHubObject(image: .gameHubConnectFourBoard, placement: Self.board)
            Capsule()
                .fill(Color.paeoniaInkGold.opacity(0.7 * glow))
                .frame(width: Self.rowLength, height: Self.holeSize + 16)
                .blur(radius: 14)
                .blendMode(.screen)
                .position(Self.row)
            disc
        }
    }

    private var disc: some View {
        let drop = Self.drop(at: progress / 0.55)
        let bottom = Self.holes[Self.holes.count - 1]
        let start = Self.holes[0].y - (Self.holes[1].y - Self.holes[0].y)
        return Image(.gameHubConnectFourDiscPink)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: Self.holeSize + 4, height: Self.holeSize + 4)
            .position(x: bottom.x, y: start + (bottom.y - start) * drop.fall - drop.lift)
            .mask {
                Path { path in
                    for hole in Self.holes {
                        path.addEllipse(in: CGRect(
                            x: hole.x - Self.holeSize / 2,
                            y: hole.y - Self.holeSize / 2,
                            width: Self.holeSize,
                            height: Self.holeSize
                        ))
                    }
                }
            }
    }

    /// How far the disc has fallen (0 to 1) and how far a bounce lifts it, in pixels, when
    /// the drop is `time` (0 to 1) of the way through. Gravity speeds the fall up, then two
    /// bounces, the second smaller.
    private static func drop(at time: Double) -> (fall: CGFloat, lift: CGFloat) {
        let time = min(max(time, 0), 1)
        let landing = 0.5
        guard time >= landing else {
            let gravity = time / landing
            return (gravity * gravity, 0)
        }
        let rest = (time - landing) / (1 - landing)
        if rest < 0.6 {
            return (1, 7 * arc(rest / 0.6))
        }
        return (1, 2 * arc((rest - 0.6) / 0.4))
    }

    /// A hop that starts and ends at 0 and peaks at 1 in the middle.
    private static func arc(_ fraction: Double) -> CGFloat {
        4 * fraction * (1 - fraction)
    }
}

#if DEBUG
#Preview {
    ConnectFourHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
