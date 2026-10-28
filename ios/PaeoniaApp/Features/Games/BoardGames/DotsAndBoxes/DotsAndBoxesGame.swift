import SwiftUI

/// Dots and Boxes on the Games tab: its hub model and its screen.
enum DotsAndBoxesGame {
    /// A line snaps in. A closed box pops in after it.
    static let timing = BoardGameMoveTiming(
        mine: .milliseconds(350),
        partner: .milliseconds(600),
        openLeadIn: .milliseconds(600)
    )

    static func hubModel(dependencies: GamesDependencies) -> BoardGameHubModel<DotsAndBoxesBoard> {
        BoardGameHubModel(
            kind: .dotsAndBoxes,
            name: .dotsAndBoxesName,
            subtitle: .dotsAndBoxesHubSubtitle,
            timing: timing,
            dependencies: dependencies,
            artwork: { AnyView(DotsAndBoxesHubArtwork()) },
            screen: { AnyView(DotsAndBoxesScreen(viewModel: $0, history: $1)) },
            replayBoard: { AnyView(BoardGameReplayBoards.dotsAndBoxes($0)) }
        )
    }
}

struct DotsAndBoxesScreen: View {
    let viewModel: BoardGameViewModel<DotsAndBoxesBoard>
    let history: GameHistoryLink?

    var body: some View {
        BoardGameScreen(viewModel: viewModel, title: .dotsAndBoxesName, history: history) {
            DotsAndBoxesBoardView(
                board: viewModel.board,
                lastMove: viewModel.lastMove,
                styles: viewModel.styles,
                me: viewModel.me,
                canPlay: viewModel.canPlay,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                photo: viewModel.photo,
                partnerName: viewModel.partnerName,
                onPlay: { line in Task { await viewModel.play(line) } }
            )
        }
    }
}
