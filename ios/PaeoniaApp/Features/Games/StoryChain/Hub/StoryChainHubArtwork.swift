import SwiftUI

/// The Story Chain card's scene: a notebook page with lines in both partners' inks, one
/// line in gold, the fountain pen, and an ink bottle. The beat pops a peony bud up after
/// the last line, like the flower that closes a finished story. It follows
/// `docs/games/hub-artwork.md`.
struct StoryChainHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.2) { progress in
            StoryChainHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. Spots on the notebook are fractions of
/// `GameHubStoryChainNotebook`.
private struct StoryChainHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let notebook = GameHubPlacement(base: CGPoint(x: 440, y: 640), width: 470, aspect: 1.133)
    private static let pen = GameHubPlacement(base: CGPoint(x: 770, y: 440), width: 290, aspect: 1.585)
    private static let ink = GameHubPlacement(base: CGPoint(x: 800, y: 640), width: 130, aspect: 0.796)

    var body: some View {
        ZStack {
            GameHubObject(image: .gameHubStoryChainNotebook, placement: Self.notebook)
            GameHubObject(image: .gameHubStoryChainInk, placement: Self.ink)
            GameHubObject(image: .gameHubStoryChainPen, placement: Self.pen, shadow: false)
            GameHubBeatPop(
                image: .gameHubPeonyBud,
                center: Self.notebook.point(0.725, 0.69),
                size: 76,
                progress: progress,
                start: 0.1
            )
        }
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
