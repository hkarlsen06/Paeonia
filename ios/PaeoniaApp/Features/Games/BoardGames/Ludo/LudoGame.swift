import SwiftUI

/// Ludo on the Games tab: its hub model and its screen.
enum LudoGame {
    /// My move covers the hops and a send-home. The partner's also covers the
    /// 0.8 s tumble of their die, which happens before their move exists on my
    /// phone.
    static let timing = BoardGameMoveTiming(mine: .milliseconds(1_400), partner: .milliseconds(2_400))

    static func hubModel(dependencies: GamesDependencies) -> BoardGameHubModel<LudoBoard> {
        BoardGameHubModel(
            kind: .ludo,
            name: .ludoName,
            timing: timing,
            dependencies: dependencies,
            artwork: { AnyView(LudoHubArtwork()) },
            screen: { AnyView(LudoScreen(viewModel: $0)) }
        )
    }
}

struct LudoScreen: View {
    let viewModel: BoardGameViewModel<LudoBoard>

    @State private var roll: LudoRollModel

    init(viewModel: BoardGameViewModel<LudoBoard>) {
        self.viewModel = viewModel
        _roll = State(initialValue: LudoRollModel(
            context: { LudoRollContext(viewModel) },
            store: .cache(for: viewModel),
            play: { move in await viewModel.play(move) }
        ))
    }

    var body: some View {
        BoardGameScreen(viewModel: viewModel, title: .ludoName, hint: roll.hint?.text, boardBleeds: true) {
            LudoBoardView(
                board: viewModel.board,
                lastMove: viewModel.lastMove,
                styles: viewModel.styles,
                me: viewModel.me,
                die: roll.die,
                movableChoices: roll.movableChoices,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                partnerName: viewModel.partnerName,
                onRoll: roll.roll,
                onChoose: { choice in Task { await roll.choose(choice) } }
            )
        }
        // The saved roll belongs to the signed-in person, so it is read once
        // they are known, and again if they change.
        .task(id: viewModel.currentUserID) {
            guard viewModel.currentUserID != nil else { return }
            await roll.restore()
        }
        .onChange(of: LudoRollContext(viewModel), initial: true) {
            roll.update()
        }
        .onDisappear { roll.stop() }
        // A drag turns the board, so only the edge swipe goes back.
        .background(LudoEdgeSwipeOnly())
    }
}

extension LudoRollContext {
    /// The screen as the roll reads it.
    init(_ viewModel: BoardGameViewModel<LudoBoard>) {
        position = viewModel.snapshot.map {
            LudoPosition(
                gameID: $0.id,
                gameNumber: viewModel.displayedGameNumber,
                moveCount: viewModel.displayedMoves.count
            )
        }
        board = viewModel.board
        moves = viewModel.displayedMoves
        me = viewModel.me
        canPlay = viewModel.canPlay
        prefersReducedMotion = viewModel.prefersReducedMotion
    }
}
