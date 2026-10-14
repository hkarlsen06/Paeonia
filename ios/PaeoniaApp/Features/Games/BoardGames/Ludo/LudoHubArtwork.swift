import SwiftUI

/// The Ludo card's painting: the board with a pink and a lavender half in the center,
/// one pink pawn still on its home column and the center empty. The beat brings the
/// last pink pawn home: it pops up at the end of the pink home column, hops onto the
/// center, and the center glows gold. It follows `docs/games/hub-artwork.md`.
struct LudoHubArtwork: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubLudoPainting, duration: 1.8) { progress in
            LudoHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels. Points are where the pawn's base touches the board.
private struct LudoHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    /// The last tile of the pink home column, and the top of the dome on its seam, where
    /// the pink and lavender halves meet. The pawn reads best there, half against lavender.
    private static let column = CGPoint(x: 349, y: 314)
    private static let home = CGPoint(x: 512, y: 330)
    private static let center = CGPoint(x: 512, y: 337)
    private static let pawnHeight: CGFloat = 84
    /// Width divided by height of `GameHubLudoPawnPink`.
    private static let pawnAspect: CGFloat = 0.734
    private static let hopHeight: CGFloat = 80

    var body: some View {
        let glow = Timing.ease(progress, from: 0.55, to: 0.85)
        let settle = Timing.ease(progress, from: 0.85, to: 1)
        ZStack {
            GameHubBeatGlow(color: .paeoniaInkGold, center: Self.center, radius: 190, strength: glow - 0.3 * settle)
            pawn
        }
    }

    private var pawn: some View {
        let appear = Timing.pop(progress, from: 0, to: 0.14)
        let hop = Timing.ease(progress, from: 0.2, to: 0.5)
        let landing = Timing.ease(progress, from: 0.5, to: 0.56) - Timing.ease(progress, from: 0.56, to: 0.68)
        let feet = CGPoint(
            x: Self.column.x + (Self.home.x - Self.column.x) * hop,
            y: Self.column.y + (Self.home.y - Self.column.y) * hop - Self.hopHeight * 4 * hop * (1 - hop)
        )
        return Image(.gameHubLudoPawnPink)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: Self.pawnHeight * Self.pawnAspect, height: Self.pawnHeight)
            // A squash on landing, anchored at the base so the pawn stays on the board.
            .scaleEffect(x: 1 + 0.1 * landing, y: 1 - 0.1 * landing, anchor: .bottom)
            .scaleEffect(max(0, appear), anchor: .bottom)
            .position(x: feet.x, y: feet.y - Self.pawnHeight / 2)
    }
}

#if DEBUG
#Preview {
    LudoHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
