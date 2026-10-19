import SwiftUI

/// The Guess my spot card's scene: a folded paper map with an instant photo leaning
/// on its left side. The beat is the guess: a pink pin drops onto the map's right
/// half and plants with a small squash, and a gold glow swells under it. It follows
/// `docs/games/hub-artwork.md`.
struct GuessMySpotHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.6) { progress in
            GuessMySpotHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. Spots on the map are fractions of `GameHubGuessMySpotMap`,
/// measured from its pixels.
private struct GuessMySpotHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let map = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 600, aspect: 1.957)
    /// Where the pin's stem plants: open land in the map's top right panel, clear of both folds.
    private static let plant = map.point(0.78, 0.33)
    private static let pinHeight: CGFloat = 170
    private static let pinAspect: CGFloat = 0.773
    /// Where the stem's tip is, as a fraction of the pin image's height.
    private static let tipDown: CGFloat = 1.0
    private static let dropHeight: CGFloat = 150

    var body: some View {
        let glow = Timing.ease(progress, from: 0.5, to: 0.8) - 0.35 * Timing.ease(progress, from: 0.8, to: 1)
        ZStack {
            GameHubObject(image: .gameHubGuessMySpotMap, placement: Self.map)
            GameHubBeatGlow(color: .paeoniaInkGold, center: Self.plant, radius: 150, strength: glow)
            pin
        }
    }

    private var pin: some View {
        let appear = Timing.ease(progress, from: 0, to: 0.12)
        let fall = Timing.ease(progress, from: 0.05, to: 0.45)
        let landing = Timing.ease(progress, from: 0.45, to: 0.52) - Timing.ease(progress, from: 0.52, to: 0.66)
        let tipY = Self.plant.y - Self.dropHeight * (1 - fall * fall)
        return Image(.gameHubGuessMySpotPin)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: Self.pinHeight * Self.pinAspect, height: Self.pinHeight)
            // A squash on planting, anchored at the stem's tip so it stays in the map.
            .scaleEffect(x: 1 + 0.08 * landing, y: 1 - 0.08 * landing, anchor: .bottom)
            .opacity(appear)
            .position(x: Self.plant.x, y: tipY - Self.pinHeight * Self.tipDown / 2)
    }
}

#if DEBUG
#Preview {
    GuessMySpotHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
