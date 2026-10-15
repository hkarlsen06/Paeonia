import Observation
import SwiftUI

/// Plays a finished board game again, one move at a time and faster than it was
/// played. The slider can jump to any move, and the board shows the game as it
/// stood after that move.
@MainActor
@Observable
final class BoardGameReplayModel<Board: BoardGameRules> {
    /// The time between two moves.
    nonisolated static var moveInterval: Duration { .milliseconds(320) }
    /// The pause after the last move before the outcome highlight plays, so the
    /// board's last close finishes first.
    nonisolated static var outcomeDelay: Duration { .milliseconds(450) }

    let game: RemoteBoardGameHistoryGame
    /// The player this person was in that game.
    let me: BoardPlayer
    /// How many moves the board shows, from 0 to `moveCount`.
    private(set) var step = 0
    private(set) var isPlaying = false
    private(set) var board: Board = .initial
    private(set) var lastMove: BoardMoveEvent?
    private(set) var showsOutcome = false

    @ObservationIgnored private let movers: [BoardPlayer]
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        game: RemoteBoardGameHistoryGame,
        userID: UUID?,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.game = game
        self.sleep = sleep
        me = game.firstUserID == userID ? .one : .two
        // The server checked every move, so this only fails on a broken record.
        // The board then stays empty and the slider has nowhere to go.
        movers = Board.movers(game.moves) ?? []
    }

    var moveCount: Int {
        movers.count
    }

    var isAtEnd: Bool {
        step == moveCount
    }

    // MARK: Controls

    /// Plays from where the board is, or from the start once it is at the end.
    func play() {
        guard moveCount > 0 else { return }
        if isAtEnd {
            show(0)
        }
        isPlaying = true
        task?.cancel()
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func pause() {
        isPlaying = false
        task?.cancel()
        task = nil
    }

    /// Jumps to a move. The replay stops, so the board stays where it was put.
    func scrub(to newStep: Int) {
        pause()
        show(newStep)
        showsOutcome = isAtEnd && board.outcome != nil
    }

    // MARK: Playing

    private func run() async {
        while isPlaying, !isAtEnd {
            do {
                try await sleep(Self.moveInterval)
            } catch {
                return
            }
            guard isPlaying, !Task.isCancelled else { return }
            show(step + 1)
        }
        isPlaying = false
        task = nil
        guard board.outcome != nil, (try? await sleep(Self.outcomeDelay)) != nil, isAtEnd else { return }
        showsOutcome = true
    }

    /// Puts the board after `newStep` moves on screen. The last move is the one
    /// the board animates.
    private func show(_ newStep: Int) {
        let target = min(max(newStep, 0), moveCount)
        step = target
        showsOutcome = false
        board = Board.replay(Array(game.moves.prefix(target))) ?? .initial
        lastMove = target == 0 ? nil : BoardMoveEvent(
            number: target,
            move: game.moves[target - 1],
            player: movers[target - 1],
            isMine: movers[target - 1] == me
        )
    }
}
