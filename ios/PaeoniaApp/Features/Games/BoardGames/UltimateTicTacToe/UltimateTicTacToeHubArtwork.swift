import SwiftUI

/// The Ultimate Tic-Tac-Toe card's painting: nine small boards with hearts and rings in
/// them, and three hearts in a diagonal on the middle left board. The beat strikes a gold
/// line through those three hearts, winning that board. It follows
/// `docs/games/hub-artwork.md`.
struct UltimateTicTacToeHubArtwork: View {
    var body: some View {
        GameHubArtwork(plate: .gameHubUltimateTicTacToePainting, duration: 1) { progress in
            UltimateTicTacToeHubBeat(progress: progress)
        }
    }
}

/// In the painting's pixels. The line draws from the first heart to the third.
private struct UltimateTicTacToeHubBeat: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let drawn = GameHubArtworkTiming.ease(progress, from: 0, to: 0.8)
        Path { path in
            path.move(to: CGPoint(x: 221, y: 304))
            path.addLine(to: CGPoint(x: 377, y: 416))
        }
        .trimmedPath(from: 0, to: drawn)
        .stroke(Color.paeoniaInkGold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
        .shadow(color: Color.paeoniaInkGold.opacity(0.9 * drawn), radius: 10)
    }
}

#if DEBUG
#Preview {
    UltimateTicTacToeHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
