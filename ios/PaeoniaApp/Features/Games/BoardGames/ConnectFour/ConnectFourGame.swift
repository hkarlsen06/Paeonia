import SwiftUI

/// Connect Four on the Games tab: its hub model and its screen.
enum ConnectFourGame {
    /// The partner's disc hovers for 0.25 s before it falls. Both bounce. Each
    /// move takes as long as its disc falls, so the outcome starts 0.15 s after
    /// the winning disc stops. `mine` and `partner` are the longest drops.
    static let timing = BoardGameMoveTiming(
        mine: .milliseconds(770),
        partner: .milliseconds(1_020),
        openLeadIn: .milliseconds(600),
        exact: { ConnectFourDropMotion.showDuration(of: $0, on: $1) }
    )

    static func hubModel(dependencies: GamesDependencies) -> BoardGameHubModel<ConnectFourBoard> {
        BoardGameHubModel(
            kind: .connectFour,
            name: .connectFourName,
            subtitle: .connectFourHubSubtitle,
            timing: timing,
            dependencies: dependencies,
            artwork: { AnyView(ConnectFourHubArtwork()) },
            screen: { AnyView(ConnectFourScreen(viewModel: $0)) },
            replayBoard: { AnyView(BoardGameReplayBoards.connectFour($0)) }
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
