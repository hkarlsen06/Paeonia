import SwiftUI

/// The Exquisite Corpse card's painting: a folded strip in three parts with a kitten's
/// head, a sweater with a heart, and duck feet, drawn by two people, with a pink and a
/// blue crayon. The beat swells a pink light behind the sweater's heart, where the three
/// parts come together. It follows `docs/games/hub-artwork.md`.
struct ExquisiteCorpseHubPainting: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubExquisiteCorpsePainting, duration: 1.6) { progress in
            ExquisiteCorpseHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels. The glow rises past its resting strength and settles.
private struct ExquisiteCorpseHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let rise = GameHubArtworkTiming.ease(progress, from: 0, to: 0.5)
        let settle = GameHubArtworkTiming.ease(progress, from: 0.5, to: 1)
        GameHubBeatGlow(
            color: .paeoniaAccentPrimary,
            center: CGPoint(x: 547, y: 407),
            radius: 260,
            strength: rise - 0.5 * settle
        )
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
