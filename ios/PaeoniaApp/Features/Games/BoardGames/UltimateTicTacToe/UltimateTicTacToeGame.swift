import SwiftUI

/// Ultimate Tic-Tac-Toe on the Games tab: its hub model and its screen.
enum UltimateTicTacToeGame {
    static func hubModel(dependencies: GamesDependencies) -> BoardGameHubModel<UltimateTicTacToeBoard> {
        BoardGameHubModel(
            kind: .ultimateTicTacToe,
            name: .ultimateTicTacToeName,
            subtitle: .ultimateTicTacToeHubSubtitle,
            timing: UltimateTicTacToeBoardView.moveTiming,
            dependencies: dependencies,
            artwork: { AnyView(UltimateTicTacToeHubArtwork()) },
            screen: { AnyView(UltimateTicTacToeScreen(viewModel: $0)) },
            replayBoard: { replay in
                AnyView(UltimateTicTacToeBoardView(
                    board: replay.board,
                    lastMove: replay.lastMove,
                    styles: replay.styles,
                    me: replay.me,
                    canPlay: false,
                    pick: .constant(.none),
                    showsOutcome: replay.showsOutcome,
                    bloomSeed: replay.bloomSeed,
                    partnerName: replay.partnerName,
                    isReplay: true
                ))
            }
        )
    }
}

/// The game screen. It holds what I picked on my turn, which the board shows
/// and "Lock in" under it plays.
struct UltimateTicTacToeScreen: View {
    let viewModel: BoardGameViewModel<UltimateTicTacToeBoard>

    @State private var pick = UltimateTicTacToePick.none

    var body: some View {
        BoardGameScreen(
            viewModel: viewModel,
            title: .ultimateTicTacToeName,
            hint: pick.asksForBoard(on: viewModel.board, canPlay: viewModel.canPlay)
                ? .ultimateTicTacToeHintChooseBoard : nil,
            history: .boardGameHistory(.ultimateTicTacToe),
            action: lockIn
        ) {
            UltimateTicTacToeBoardView(
                board: viewModel.board,
                lastMove: viewModel.lastMove,
                styles: viewModel.styles,
                me: viewModel.me,
                canPlay: viewModel.canPlay,
                pick: $pick,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                partnerName: viewModel.partnerName
            )
            .onChange(of: viewModel.board) { pick = .none }
            .onChange(of: viewModel.canPlay) { pick = .none }
        }
    }

    /// "Lock in" keeps its space until the game ends, so the board never moves.
    /// It hides on my partner's turn, waits disabled until I pick a cell, and
    /// then plays it.
    private var lockIn: BoardGameScreenAction? {
        guard viewModel.board.outcome == nil else { return nil }
        let move = pick.move(on: viewModel.board)
        return BoardGameScreenAction(
            title: .ultimateTicTacToeLockIn,
            state: !viewModel.canPlay ? .hidden : move == nil ? .disabled : .enabled,
            identifier: "ultimateTicTacToe.lockIn"
        ) {
            guard let move else { return }
            GameSound.mark.play()
            Task { await viewModel.play(move) }
        }
    }
}
