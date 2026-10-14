import SwiftUI

/// The Connect Four card's painting: a cream board with both partners' discs in it, three
/// pink discs in a row at the bottom and the fourth hole still empty. The beat drops the
/// last pink disc into that hole, and the row lights up gold. It follows
/// `docs/games/hub-artwork.md`.
struct ConnectFourHubArtwork: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubConnectFourPainting, duration: 1.6) { progress in
            ConnectFourHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels. The disc slides down inside the empty hole, masked to it, so
/// it reads as dropping behind the board's face, and bounces twice. Then the row glows.
private struct ConnectFourHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let hole = CGPoint(x: 597, y: 481)
    private static let holeSize: CGFloat = 44
    /// The middle of the winning row, from the first pink disc to the empty hole.
    private static let row = CGPoint(x: 494, y: 481)
    private static let rowLength: CGFloat = 270

    var body: some View {
        let glow = Timing.ease(progress, from: 0.62, to: 0.9)
        ZStack {
            Capsule()
                .fill(Color.paeoniaInkGold.opacity(0.7 * glow))
                .frame(width: Self.rowLength, height: Self.holeSize + 22)
                .blur(radius: 18)
                .blendMode(.screen)
                .position(Self.row)
            disc
                .position(Self.hole)
        }
    }

    private var disc: some View {
        let drop = Self.drop(at: progress / 0.55)
        return Image(.gameHubConnectFourDiscPink)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: Self.holeSize + 4, height: Self.holeSize + 4)
            .offset(y: -Self.holeSize * 1.2 * (1 - drop.fall) - drop.lift)
            .frame(width: Self.holeSize, height: Self.holeSize)
            .clipShape(Circle())
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
            return (1, 9 * arc(rest / 0.6))
        }
        return (1, 3 * arc((rest - 0.6) / 0.4))
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
