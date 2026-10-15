import SwiftUI

/// The Dots and Boxes card's scene: a board of pearls and lines where every closed box
/// shows a piece of a sunset photo. The beat swells a warm light behind the board, like
/// the photo's sun coming up through the boxes. It follows `docs/games/hub-artwork.md`.
struct DotsAndBoxesHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.8) { progress in
            DotsAndBoxesHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. The glow rises past its resting strength and settles.
private struct DotsAndBoxesHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let board = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 540, aspect: 1.227)

    var body: some View {
        let rise = GameHubArtworkTiming.ease(progress, from: 0, to: 0.5)
        let settle = GameHubArtworkTiming.ease(progress, from: 0.5, to: 1)
        ZStack {
            GameHubObject(image: .gameHubDotsAndBoxesBoard, placement: Self.board)
            GameHubBeatGlow(
                color: .paeoniaInkGold,
                center: Self.board.point(0.5, 0.5),
                radius: 320,
                strength: rise - 0.45 * settle
            )
        }
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
