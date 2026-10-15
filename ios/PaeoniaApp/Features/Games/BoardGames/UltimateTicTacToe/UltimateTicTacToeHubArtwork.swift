import SwiftUI

/// The Ultimate Tic-Tac-Toe card's scene: nine small boards on a tray, with hearts and
/// rings in them, and three hearts in a diagonal on the middle left board. The beat
/// strikes a gold line through those three hearts, winning that board. It follows
/// `docs/games/hub-artwork.md`.
struct UltimateTicTacToeHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1) { progress in
            UltimateTicTacToeHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. Spots on the tray are fractions of
/// `GameHubUltimateTicTacToeBoard`. The line draws from the first heart to the third.
private struct UltimateTicTacToeHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let board = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 510, aspect: 1.163)

    var body: some View {
        let drawn = GameHubArtworkTiming.ease(progress, from: 0, to: 0.8)
        ZStack {
            GameHubObject(image: .gameHubUltimateTicTacToeBoard, placement: Self.board)
            Path { path in
                path.move(to: Self.board.point(0.156, 0.386))
                path.addLine(to: Self.board.point(0.303, 0.542))
            }
            .trimmedPath(from: 0, to: drawn)
            .stroke(Color.paeoniaInkGold, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            .shadow(color: Color.paeoniaInkGold.opacity(0.9 * drawn), radius: 8)
        }
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
