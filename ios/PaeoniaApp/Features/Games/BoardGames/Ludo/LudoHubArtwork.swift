import SwiftUI

/// The Ludo card's scene: the board with one pawn of each partner on the track and the
/// dome in the center empty, split pink and lavender. The beat brings a pink pawn home:
/// it pops up on the last pink tile before the dome, hops onto the dome's seam, and the
/// dome glows gold. It follows `docs/games/hub-artwork.md`.
struct LudoHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.8) { progress in
            LudoHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. Spots on the board are fractions of `GameHubLudoBoard`, and the
/// pawn's points are where its base touches the board.
private struct LudoHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let board = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 600, aspect: 1.370)
    /// The last pink tile on the left arm, right before the dome.
    private static let column = board.point(0.351, 0.443)
    /// The middle of the dome on its seam. Higher up, the base sits on the dome's far
    /// slope and the pawn looks pasted on.
    private static let home = board.point(0.499, 0.427)
    private static let dome = board.point(0.499, 0.404)
    /// `GameHubLudoPawnPink` is the board's own pink pawn, cut out of `GameHubLudoBoard`,
    /// so it matches the board's camera and light. This is its height on the board.
    private static let pawnHeight: CGFloat = 81
    private static let pawnAspect: CGFloat = 0.696
    private static let hopHeight: CGFloat = 60

    var body: some View {
        let glow = Timing.ease(progress, from: 0.55, to: 0.85)
        let settle = Timing.ease(progress, from: 0.85, to: 1)
        ZStack {
            GameHubObject(image: .gameHubLudoBoard, placement: Self.board)
            GameHubBeatGlow(color: .paeoniaInkGold, center: Self.dome, radius: 120, strength: glow - 0.3 * settle)
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
