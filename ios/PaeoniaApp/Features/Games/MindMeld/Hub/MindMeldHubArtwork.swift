import SwiftUI

/// The Mind Meld card's painting: two blank word cards leaning together, one glowing in
/// each partner's color, with a green light where they touch. The beat opens a peony
/// where they meet, as in the game when both partners say the same word. It follows
/// `docs/games/hub-artwork.md`.
struct MindMeldHubArtwork: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubMindMeldPainting, duration: 1.4) { progress in
            MindMeldHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels. A green glow swells at the seam, then the peony opens on it.
private struct MindMeldHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let meeting = CGPoint(x: 513, y: 523)

    var body: some View {
        ZStack {
            GameHubBeatGlow(
                color: .paeoniaSuccess,
                center: Self.meeting,
                radius: 180,
                strength: GameHubArtworkTiming.ease(progress, from: 0, to: 0.4)
            )
            GameHubBeatPop(image: .gameHubPeony, center: Self.meeting, size: 150, progress: progress, start: 0.25)
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
