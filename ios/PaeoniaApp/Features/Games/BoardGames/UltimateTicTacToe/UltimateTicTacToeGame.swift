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
                    showsOutcome: replay.showsOutcome,
                    bloomSeed: replay.bloomSeed,
                    partnerName: replay.partnerName,
                    isReplay: true,
                    onPlay: { _ in }
                ))
            }
        )
    }
}

struct UltimateTicTacToeScreen: View {
    let viewModel: BoardGameViewModel<UltimateTicTacToeBoard>

    var body: some View {
        BoardGameScreen(
            viewModel: viewModel,
            title: .ultimateTicTacToeName,
            history: .boardGameHistory(.ultimateTicTacToe)
        ) {
            UltimateTicTacToeBoardView(
                board: viewModel.board,
                lastMove: viewModel.lastMove,
                styles: viewModel.styles,
                me: viewModel.me,
                canPlay: viewModel.canPlay,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                partnerName: viewModel.partnerName,
                onPlay: { cell in Task { await viewModel.play(cell) } }
            )
        }
    }
}
