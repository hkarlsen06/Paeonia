import Foundation

/// A move saved on this phone until the server takes it.
nonisolated struct BoardGameMovePayload: Codable, Equatable, Sendable {
    let kind: GameKind
    let gameID: UUID
    let gameNumber: Int
    /// The game's version when the move was made. The server refuses the move
    /// when the game has changed since.
    let expectedVersion: Int
    let move: Int
    /// Only on the first move of the game, by the partner who started it.
    let stake: String?
    /// Ludo only: the color this player picked for the game. It goes with this
    /// player's first move of the game, and only when it differs from their color.
    let ludoColor: LudoColor?
    let createdAt: Date
}

/// "Play again", saved on this phone until the server takes it.
nonisolated struct BoardGameRematchPayload: Codable, Equatable, Sendable {
    let kind: GameKind
    let gameID: UUID
    /// The version of the finished game.
    let expectedVersion: Int
    let createdAt: Date
}

/// One unsent action, in the order it was made.
nonisolated enum BoardGamePendingAction: Equatable, Sendable {
    case move(BoardGameMovePayload)
    case rematch(BoardGameRematchPayload)

    var kind: GameKind {
        switch self {
        case let .move(payload): payload.kind
        case let .rematch(payload): payload.kind
        }
    }
}

/// The game as this phone shows it: the server's game with this phone's
/// unsent actions on top, then the partner's moves that came live and the
/// server does not have yet.
nonisolated struct BoardGameSnapshot<Board: BoardGameRules>: Equatable, Sendable {
    let id: UUID
    let gameNumber: Int
    /// The version the next action names.
    let version: Int
    let firstUserID: UUID
    let moves: [Int]
    let board: Board
    let stake: String?
    /// Ludo only: the piece colors, with the picks of the moves on top.
    let myColor: LudoColor?
    let partnerColor: LudoColor?
    let photoMediaAssetID: UUID?
    let myWins: Int
    let partnerWins: Int
    let draws: Int
    let gamesFinished: Int
    let previous: RemoteBoardGameEnding?
    /// Actions of this phone on top of the server's game that it has not taken yet.
    let unsentCount: Int
    /// A move of the partner's that came live is on top of the server's game.
    /// The next move here names the version after it, so it waits until the
    /// server has the partner's move.
    let hasUnconfirmedPartnerMove: Bool

    /// The player this phone plays as in the current game.
    func player(for userID: UUID) -> BoardPlayer {
        firstUserID == userID ? .one : .two
    }

    var isFinished: Bool {
        board.outcome != nil
    }
}

nonisolated extension BoardGameSnapshot {
    /// It is this person's move, named by the partner's move that handed it over. A
    /// Dots and Boxes box or a Ludo 6 keeps the turn, so the name stays the same through
    /// this person's own extra moves. A game this person moves first in counts as a
    /// handover only when the partner started it with "Play again". `startedHere` says
    /// this phone started it. The first game always goes first to whoever created it.
    func attention(userID: UUID, startedHere: Bool) -> GameAttention {
        let me = player(for: userID)
        guard board.outcome == nil, board.next == me, let movers = Board.movers(moves) else {
            return GameAttention()
        }
        if let partnerMove = movers.lastIndex(where: { $0 != me }) {
            return GameAttention(turn: "game \(gameNumber) move \(partnerMove + 1)")
        }
        guard gameNumber > 1, !startedHere else { return GameAttention() }
        return GameAttention(turn: "game \(gameNumber) started")
    }
}

/// Builds the snapshot from the server's game, the unsent actions and the
/// partner's live moves. Pure: no clock, no storage.
///
/// An action applies only when it names the version the game has reached, so
/// an action the server already took (its answer can arrive before the action
/// leaves the queue) or can no longer take is skipped instead of applied twice.
/// The partner's live moves follow the same rule after this phone's own actions,
/// because the partner made them on a board that already had those.
nonisolated enum BoardGameResolver {
    static func resolve<Board: BoardGameRules>(
        _ game: RemoteBoardGame,
        pending: [BoardGamePendingAction],
        partnerMoves: [BoardGameMovePayload] = [],
        userID: UUID,
        partnerID: UUID,
        as _: Board.Type = Board.self
    ) -> BoardGameSnapshot<Board>? {
        guard let board = Board.replay(game.moves) else { return nil }
        var state = State(game: game, board: board)
        var unsentCount = 0
        for action in pending where action.kind == game.kind {
            switch action {
            case let .move(payload):
                if state.apply(payload, gameID: game.id, moverID: userID, userID: userID) {
                    unsentCount += 1
                }
            case let .rematch(payload):
                if state.apply(payload, gameID: game.id, userID: userID, partnerID: partnerID) {
                    unsentCount += 1
                }
            }
        }
        var hasUnconfirmedPartnerMove = false
        for payload in partnerMoves where payload.kind == game.kind {
            if state.apply(payload, gameID: game.id, moverID: partnerID, userID: userID) {
                hasUnconfirmedPartnerMove = true
            }
        }
        return BoardGameSnapshot(
            id: game.id,
            gameNumber: state.gameNumber,
            version: state.version,
            firstUserID: state.firstUserID,
            moves: state.moves,
            board: state.board,
            stake: state.stake,
            myColor: state.myColor,
            partnerColor: state.partnerColor,
            photoMediaAssetID: state.photoMediaAssetID,
            myWins: state.myWins,
            partnerWins: state.partnerWins,
            draws: state.draws,
            gamesFinished: state.gamesFinished,
            previous: state.previous,
            unsentCount: unsentCount,
            hasUnconfirmedPartnerMove: hasUnconfirmedPartnerMove
        )
    }

    private struct State<Board: BoardGameRules> {
        var board: Board
        var gameNumber: Int
        var version: Int
        var firstUserID: UUID
        var moves: [Int]
        var stake: String?
        var myColor: LudoColor?
        var partnerColor: LudoColor?
        var photoMediaAssetID: UUID?
        var myWins: Int
        var partnerWins: Int
        var draws: Int
        var gamesFinished: Int
        var previous: RemoteBoardGameEnding?

        init(game: RemoteBoardGame, board: Board) {
            self.board = board
            gameNumber = game.gameNumber
            version = game.version
            firstUserID = game.firstUserID
            moves = game.moves
            stake = game.stake
            myColor = game.myColor
            partnerColor = game.partnerColor
            photoMediaAssetID = game.photoMediaAssetID
            myWins = game.myWins
            partnerWins = game.partnerWins
            draws = game.draws
            gamesFinished = game.gamesFinished
            previous = game.previous
        }

        /// A move by `moverID`, this person or the partner, on the game it was
        /// made on, at the version it names. Returns whether it applied.
        mutating func apply(_ payload: BoardGameMovePayload, gameID: UUID, moverID: UUID, userID: UUID) -> Bool {
            let mover: BoardPlayer = firstUserID == moverID ? .one : .two
            guard payload.gameID == gameID,
                  payload.gameNumber == gameNumber,
                  payload.expectedVersion == version,
                  board.outcome == nil,
                  board.next == mover,
                  let after = board.applying(payload.move)
            else { return false }
            if moves.isEmpty, mover == .one, let stake = payload.stake {
                self.stake = stake
            }
            // The server takes a pick with a player's first move, and not when
            // the other player already has that color.
            if let color = payload.ludoColor, Board.movers(moves)?.contains(mover) == false {
                if moverID == userID {
                    if myColor != nil, color != partnerColor { myColor = color }
                } else if partnerColor != nil, color != myColor {
                    partnerColor = color
                }
            }
            moves.append(payload.move)
            version += 1
            board = after
            if let outcome = after.outcome {
                count(outcome, userID: userID)
            }
            return true
        }

        /// "Play again" on the finished game at the version it names. Returns
        /// whether it applied.
        mutating func apply(
            _ payload: BoardGameRematchPayload,
            gameID: UUID,
            userID: UUID,
            partnerID: UUID
        ) -> Bool {
            guard payload.gameID == gameID,
                  payload.expectedVersion == version,
                  let outcome = board.outcome
            else { return false }
            let secondUserID = firstUserID == userID ? partnerID : userID
            previous = RemoteBoardGameEnding(
                gameNumber: gameNumber,
                firstUserID: firstUserID,
                moves: moves,
                winnerUserID: outcome.winner.map { $0 == .one ? firstUserID : secondUserID },
                winLine: outcome.line,
                stake: stake,
                photoMediaAssetID: photoMediaAssetID,
                finishedAt: payload.createdAt
            )
            // The partner who did not start the last game starts the next one.
            firstUserID = secondUserID
            gameNumber += 1
            moves = []
            stake = nil
            // The server picks the next hidden photo.
            photoMediaAssetID = nil
            version += 1
            board = .initial
            return true
        }

        private mutating func count(_ outcome: BoardOutcome, userID: UUID) {
            gamesFinished += 1
            guard let winner = outcome.winner else {
                draws += 1
                return
            }
            if (winner == .one) == (firstUserID == userID) {
                myWins += 1
            } else {
                partnerWins += 1
            }
        }
    }
}
