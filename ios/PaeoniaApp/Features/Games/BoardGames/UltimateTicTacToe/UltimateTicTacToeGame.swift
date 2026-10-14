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
            screen: { AnyView(UltimateTicTacToeScreen(viewModel: $0)) }
        )
    }
}

struct UltimateTicTacToeScreen: View {
    let viewModel: BoardGameViewModel<UltimateTicTacToeBoard>

    var body: some View {
        BoardGameScreen(viewModel: viewModel, title: .ultimateTicTacToeName) {
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
