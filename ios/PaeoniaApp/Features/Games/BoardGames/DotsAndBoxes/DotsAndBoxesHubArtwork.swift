import SwiftUI

/// The Dots and Boxes card's painting: a board of pearls and lines where every closed box
/// shows a piece of a sunset photo. The beat swells a warm light behind the board, like
/// the photo's sun coming up through the boxes. It follows `docs/games/hub-artwork.md`.
struct DotsAndBoxesHubArtwork: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubDotsAndBoxesPainting, duration: 1.8) { progress in
            DotsAndBoxesHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels. The glow rises past its resting strength and settles.
private struct DotsAndBoxesHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let rise = GameHubArtworkTiming.ease(progress, from: 0, to: 0.5)
        let settle = GameHubArtworkTiming.ease(progress, from: 0.5, to: 1)
        GameHubBeatGlow(
            color: .paeoniaInkGold,
            center: CGPoint(x: 512, y: 385),
            radius: 360,
            strength: rise - 0.45 * settle
        )
    }
}

#if DEBUG
#Preview {
    DotsAndBoxesHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
