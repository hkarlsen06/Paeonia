import SwiftUI

/// The Consensio card's scene: a cream rail with gold end caps and one pink pin
/// planted in it. The beat is the partner's guess: a lavender pin drops in close
/// beside the pink one and plants with a small squash, and a gold glow swells
/// between the two. It follows `docs/games/hub-artwork.md`.
struct ConsensioHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.6) { progress in
            ConsensioHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. Spots on the rail are fractions of `GameHubConsensioRail`,
/// measured from its pixels.
private struct ConsensioHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let rail = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 640, aspect: 2.439)
    /// Where the lavender pin's stem plants: the top surface at 62 percent along.
    private static let plant = rail.point(0.620, 0.639)
    /// Between the two pins' heads, for the glow.
    private static let between = rail.point(0.48, 0.30)
    /// `GameHubConsensioPin` at the size of the rail's pink pin, which stands 0.654 of the rail's height.
    private static let pinHeight: CGFloat = 196
    private static let pinAspect: CGFloat = 0.688
    /// Where the stem's tip is, as a fraction of the pin image's height.
    private static let tipDown: CGFloat = 1.0
    private static let dropHeight: CGFloat = 150

    var body: some View {
        let glow = Timing.ease(progress, from: 0.55, to: 0.85) - 0.35 * Timing.ease(progress, from: 0.85, to: 1)
        ZStack {
            GameHubObject(image: .gameHubConsensioRail, placement: Self.rail)
            GameHubBeatGlow(color: .paeoniaInkGold, center: Self.between, radius: 170, strength: glow)
            pin
        }
    }

    private var pin: some View {
        let appear = Timing.ease(progress, from: 0, to: 0.12)
        let fall = Timing.ease(progress, from: 0.05, to: 0.45)
        let landing = Timing.ease(progress, from: 0.45, to: 0.52) - Timing.ease(progress, from: 0.52, to: 0.66)
        let tipY = Self.plant.y - Self.dropHeight * (1 - fall * fall)
        return Image(.gameHubConsensioPin)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: Self.pinHeight * Self.pinAspect, height: Self.pinHeight)
            // A squash on planting, anchored at the stem's tip so it stays in the rail.
            .scaleEffect(x: 1 + 0.08 * landing, y: 1 - 0.08 * landing, anchor: .bottom)
            .opacity(appear)
            .position(x: Self.plant.x, y: tipY - Self.pinHeight * Self.tipDown / 2)
    }
}

#if DEBUG
#Preview {
    ConsensioHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
