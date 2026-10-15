import SwiftUI

/// The Mind Meld card's scene: two blank word cards leaning together, one edged in each
/// partner's color. The beat opens a peony where their tops meet, as in the game when
/// both partners say the same word. It follows `docs/games/hub-artwork.md`.
struct MindMeldHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.4) { progress in
            MindMeldHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. A green glow swells where the cards meet, then the peony opens
/// on it.
private struct MindMeldHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let cards = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 600, aspect: 1.518)
    private static let meeting = cards.point(0.503, 0.085)

    var body: some View {
        ZStack {
            GameHubObject(image: .gameHubMindMeldCards, placement: Self.cards)
            GameHubBeatGlow(
                color: .paeoniaSuccess,
                center: Self.meeting,
                radius: 180,
                strength: GameHubArtworkTiming.ease(progress, from: 0, to: 0.4)
            )
            GameHubBeatPop(image: .gameHubPeony, center: Self.meeting, size: 190, progress: progress, start: 0.25)
        }
    }
}

#if DEBUG
#Preview {
    MindMeldHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
