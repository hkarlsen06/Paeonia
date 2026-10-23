#if DEBUG
import SwiftUI

private enum UltimateTicTacToePreviewData {
    static let styles = BoardPieceStyles(
        one: BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "H"),
        two: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "K")
    )

    /// A finished game. Player one takes boards 2, 5 and 8 on the last move.
    static let finishedMoves = [
        20, 26, 79, 63, 8, 74, 24, 56, 22, 44, 73, 11, 58,
        41, 49, 40, 42, 59, 46, 14, 52, 65, 29, 17, 76
    ]
}

/// A board both sides can play by picking a cell and locking it in, so every
/// beat shows in the canvas.
/// Player one is me. With `partnerReplies`, player two answers on its own
/// about a second after each of my moves, as a real partner would.
private struct UltimateTicTacToePlayablePreview: View {
    let partnerReplies: Bool

    @State private var board = UltimateTicTacToeBoard.initial
    @State private var lastMove: BoardMoveEvent?
    @State private var moveCount = 0
    @State private var showsOutcome = false
    @State private var pick = UltimateTicTacToePick.none

    private var canPlay: Bool {
        board.outcome == nil && (!partnerReplies || board.next == .one)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            UltimateTicTacToeBoardView(
                board: board,
                lastMove: lastMove,
                styles: UltimateTicTacToePreviewData.styles,
                me: .one,
                canPlay: canPlay,
                pick: $pick,
                showsOutcome: showsOutcome,
                bloomSeed: "preview",
                partnerName: "Kari"
            )
            Button {
                if let move = pick.move(on: board) {
                    play(move)
                }
            } label: {
                Text(verbatim: "Lock in")
            }
            .disabled(!canPlay || pick.move(on: board) == nil)
            Button {
                board = .initial
                lastMove = nil
                moveCount = 0
                showsOutcome = false
            } label: {
                Text(verbatim: "Start over")
            }
        }
        .padding(PaeoniaSpacing.space20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }

    private func play(_ move: Int) {
        apply(move)
        guard partnerReplies, board.outcome == nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(1_400))
            let legal = (0..<UltimateTicTacToeBoard.moveLimit).filter { board.isLegal($0) }
            if let reply = legal.randomElement() {
                apply(reply)
            }
        }
    }

    private func apply(_ move: Int) {
        let mover = board.next
        guard let after = board.applying(move) else { return }
        moveCount += 1
        pick = .none
        lastMove = BoardMoveEvent(number: moveCount, move: move, player: mover, isMine: mover == .one)
        board = after
        if after.outcome != nil {
            Task {
                try? await Task.sleep(for: .milliseconds(1_250))
                showsOutcome = true
            }
        }
    }
}

/// A finished game that shows the outcome right away. The button plays the
/// highlight again.
private struct UltimateTicTacToeFinishedPreview: View {
    @State private var showsOutcome = true

    private let board = UltimateTicTacToeBoard.replay(UltimateTicTacToePreviewData.finishedMoves) ?? .initial
    private let lastMove = BoardMoveEvent(number: 25, move: 76, player: .one, isMine: true)

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            UltimateTicTacToeBoardView(
                board: board,
                lastMove: lastMove,
                styles: UltimateTicTacToePreviewData.styles,
                me: .one,
                canPlay: false,
                pick: .constant(.none),
                showsOutcome: showsOutcome,
                bloomSeed: "preview",
                partnerName: "Kari"
            )
            Button {
                showsOutcome = false
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    showsOutcome = true
                }
            } label: {
                Text(verbatim: "Play the highlight")
            }
        }
        .padding(PaeoniaSpacing.space20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview("Both sides play") {
    UltimateTicTacToePlayablePreview(partnerReplies: false)
}

#Preview("Partner replies") {
    UltimateTicTacToePlayablePreview(partnerReplies: true)
}

#Preview("Finished") {
    UltimateTicTacToeFinishedPreview()
}
#endif
