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
/// and "Lock in" under it plays. While both partners have the game open, each
/// pick also shows faintly on the other phone (`UltimateTicTacToeLiveLink`).
struct UltimateTicTacToeScreen: View {
    let viewModel: BoardGameViewModel<UltimateTicTacToeBoard>

    @State private var pick = UltimateTicTacToePick.none
    /// What my partner last picked, as their phone sent it.
    @State private var partnerPick: UltimateTicTacToeLiveMessage?
    @State private var live: UltimateTicTacToeLiveLink?

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
                partnerPick: partnerPickOnBoard,
                showsOutcome: viewModel.showsOutcome,
                bloomSeed: viewModel.bloomSeed,
                partnerName: viewModel.partnerName
            )
            .onChange(of: viewModel.board) { pick = .none }
            .onChange(of: viewModel.canPlay) { pick = .none }
        }
        .onChange(of: myPick) { _, message in
            live?.send(message)
        }
        .task(id: viewModel.participants.coupleID) {
            startLive(coupleID: viewModel.participants.coupleID)
        }
        .onDisappear {
            live?.stop()
            live = nil
        }
    }

    /// My pick for my partner's board. It is nothing on their turn, so a new
    /// position clears what they last saw from me.
    private var myPick: UltimateTicTacToeLiveMessage {
        UltimateTicTacToeLiveMessage(
            gameNumber: viewModel.displayedGameNumber,
            moveCount: viewModel.displayedMoves.count,
            pick: viewModel.canPlay ? pick : .none
        )
    }

    /// My partner's pick while it is their turn on the board I see. It waits
    /// while moves still replay, so it never lands over their animation.
    private var partnerPickOnBoard: UltimateTicTacToePick {
        let board = viewModel.board
        guard let partnerPick,
              live?.isPartnerHere == true,
              !viewModel.isReplaying,
              board.outcome == nil,
              board.next != viewModel.me
        else {
            return .none
        }
        return partnerPick.pick(
            on: board,
            gameNumber: viewModel.displayedGameNumber,
            moveCount: viewModel.displayedMoves.count
        )
    }

    private func startLive(coupleID: UUID?) {
        live?.stop()
        partnerPick = nil
        live = coupleID
            .flatMap { viewModel.dependencies.makeBoardGameLive(.ultimateTicTacToe, $0) }
            .map { room in
                UltimateTicTacToeLiveLink(room: room) { message in
                    withAnimation(PaeoniaMotion.stateChange) { partnerPick = message }
                }
            }
        live?.send(myPick)
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
