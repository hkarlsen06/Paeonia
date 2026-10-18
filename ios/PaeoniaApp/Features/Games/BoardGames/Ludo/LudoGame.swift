import SwiftUI

/// Ludo on the Games tab: its hub model and its screen.
enum LudoGame {
    /// My move covers the hops of a winning move, at most 6 at 0.16 s, so the result
    /// follows the pawn home without a wait. The partner's also covers the throw of
    /// their die, up to 2.05 s (`LudoSceneStyle.tumbleDuration`), which happens
    /// before their move exists on my phone.
    static let timing = BoardGameMoveTiming(mine: .milliseconds(1_000), partner: .milliseconds(3_650))

    static func hubModel(dependencies: GamesDependencies) -> BoardGameHubModel<LudoBoard> {
        BoardGameHubModel(
            kind: .ludo,
            name: .ludoName,
            subtitle: .ludoHubSubtitle,
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
    /// Sends and receives live rolls while the screen is open.
    @State private var live: LudoLiveLink?

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
                colors: viewModel.ludoColors,
                me: viewModel.me,
                die: roll.die,
                movableChoices: roll.movableChoices,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                partnerName: viewModel.partnerName,
                onRoll: roll.roll,
                onChoose: { choice in Task { await roll.choose(choice) } },
                onShown: { viewModel.isWaitingForBoard = false },
                onDieLanded: roll.dieLanded
            )
        }
        // The partner's moves replay once the 3D board shows, not under the loading view.
        .onAppear { viewModel.isWaitingForBoard = true }
        // The saved roll belongs to the signed-in person, so it is read once
        // they are known, and again if they change.
        .task(id: viewModel.currentUserID) {
            guard viewModel.currentUserID != nil else { return }
            await roll.restore()
        }
        .onChange(of: LudoRollContext(viewModel), initial: true) {
            roll.update()
        }
        .task(id: viewModel.participants.coupleID) {
            startLive(coupleID: viewModel.participants.coupleID)
        }
        .onDisappear {
            roll.stop()
            live?.stop()
            live = nil
        }
        // A drag throws the die, so only the edge swipe goes back.
        .background(LudoEdgeSwipeOnly())
    }

    private func startLive(coupleID: UUID?) {
        live?.stop()
        live = coupleID
            .flatMap { viewModel.dependencies.makeLudoLive($0) }
            .map { LudoLiveLink(room: $0, roll: roll) }
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
