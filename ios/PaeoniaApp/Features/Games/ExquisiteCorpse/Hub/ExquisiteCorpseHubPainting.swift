import SwiftUI

/// The Exquisite Corpse card's scene: a folded strip in three parts with a kitten's head,
/// a sweater with a heart, and duck feet, drawn by two people, with a pink and a blue
/// crayon. The beat swells a pink light behind the sweater's heart, where the three parts
/// come together. It follows `docs/games/hub-artwork.md`.
struct ExquisiteCorpseHubPainting: View {
    var body: some View {
        GameHubArtwork(duration: 1.6) { progress in
            ExquisiteCorpseHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. The glow rises past its resting strength and settles.
private struct ExquisiteCorpseHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let strip = GameHubPlacement(base: CGPoint(x: 512, y: 575), width: 720, aspect: 2.734)
    private static let pinkCrayon = GameHubPlacement(base: CGPoint(x: 330, y: 640), width: 250, aspect: 1.736)
    private static let blueCrayon = GameHubPlacement(base: CGPoint(x: 720, y: 640), width: 240, aspect: 1.794)

    var body: some View {
        let rise = GameHubArtworkTiming.ease(progress, from: 0, to: 0.5)
        let settle = GameHubArtworkTiming.ease(progress, from: 0.5, to: 1)
        ZStack {
            GameHubObject(image: .gameHubExquisiteCorpseStrip, placement: Self.strip)
            GameHubBeatGlow(
                color: .paeoniaAccentPrimary,
                center: Self.strip.point(0.497, 0.542),
                radius: 220,
                strength: rise - 0.5 * settle
            )
            GameHubObject(image: .gameHubExquisiteCorpseCrayonPink, placement: Self.pinkCrayon)
            GameHubObject(image: .gameHubExquisiteCorpseCrayonBlue, placement: Self.blueCrayon)
        }
    }
}

#if DEBUG
#Preview {
    ExquisiteCorpseHubPainting()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
