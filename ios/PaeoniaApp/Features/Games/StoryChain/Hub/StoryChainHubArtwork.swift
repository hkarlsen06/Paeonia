import SwiftUI

/// The Story Chain card's painting: a notebook page with lines in both partners' inks,
/// one word underlined in gold, the fountain pen at the end of the last line, and an ink
/// bottle. The beat pops a peony bud up after the last line, like the flower that closes
/// a finished story. It follows `docs/games/hub-artwork.md`.
struct StoryChainHubArtwork: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubStoryChainPainting, duration: 1.2) { progress in
            StoryChainHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels.
private struct StoryChainHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GameHubBeatPop(
            image: .gameHubPeonyBud,
            center: CGPoint(x: 625, y: 535),
            size: 90,
            progress: progress,
            start: 0.1
        )
    }
}

#if DEBUG
#Preview {
    StoryChainHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
