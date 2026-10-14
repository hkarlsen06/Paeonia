import SwiftUI

/// Connect Four on the Games tab: its hub model and its screen.
enum ConnectFourGame {
    /// The partner's disc hovers for 0.25 s before it falls. Both bounce once.
    static let timing = BoardGameMoveTiming(mine: .milliseconds(700), partner: .milliseconds(1_000))

    static func hubModel(dependencies: GamesDependencies) -> BoardGameHubModel<ConnectFourBoard> {
        BoardGameHubModel(
            kind: .connectFour,
            name: .connectFourName,
            timing: timing,
            dependencies: dependencies,
            artwork: { AnyView(ConnectFourHubArtwork()) },
            screen: { AnyView(ConnectFourScreen(viewModel: $0)) }
        )
    }
}

struct ConnectFourScreen: View {
    let viewModel: BoardGameViewModel<ConnectFourBoard>

    var body: some View {
        BoardGameScreen(viewModel: viewModel, title: .connectFourName) {
            ConnectFourBoardView(
                board: viewModel.board,
                lastMove: viewModel.lastMove,
                styles: viewModel.styles,
                me: viewModel.me,
                canPlay: viewModel.canPlay,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                onPlay: { column in Task { await viewModel.play(column) } },
                partnerName: viewModel.partnerName,
                // The view model plays the outcome haptic for every board game.
                playsOutcomeHaptics: false
            )
        }
    }
}
