import Foundation

/// One place in one game: the game, its number and how many moves are on the
/// board. A roll belongs to exactly one position.
nonisolated struct LudoPosition: Codable, Equatable, Hashable, Sendable {
    let gameID: UUID
    let gameNumber: Int
    let moveCount: Int
}

/// The roll this phone kept for the person's turn, so closing the app does not
/// give a new one. It lives in the board games local document, which sign out
/// clears with the rest of the board game data.
nonisolated struct LudoSavedRoll: Codable, Equatable, Sendable {
    let position: LudoPosition
    let die: Int
}

/// The line under the board that teaches Ludo while the person plays.
nonisolated enum LudoHint: Equatable, Sendable {
    /// The person's first roll of a game.
    case swipeToRoll
    /// Every pawn of the person waits in the base.
    case rollSix
    /// The last move earned another roll.
    case rollAgain
    /// The person missed a 6 with no pawn out and has this many tries left.
    case triesLeft(Int)
    /// The roll left no pawn to move, so the turn passes by itself.
    case noMove(die: Int)
}

extension LudoHint {
    var text: LocalizedStringResource {
        switch self {
        case .swipeToRoll: .ludoHintSwipeToRoll
        case .rollSix: .ludoHintRollSix
        case .rollAgain: .ludoHintRollAgain
        case let .triesLeft(tries): .ludoHintTriesLeft(tries)
        case let .noMove(die): .ludoHintNoMove(die)
        }
    }
}

/// The decisions behind the roll, with no view, clock or storage, so tests can
/// check them directly.
nonisolated enum LudoRollDecision {
    /// How long a pass waits, while the status says "No move with a 3".
    static let autoPassDelay: Duration = .milliseconds(1_200)

    static let faces = 1...LudoBoard.dieFaces

    /// Whether the turn passes by itself after the die lands. A pawn never moves
    /// by itself, even when it is the only one that can, so the person always
    /// taps it.
    static func passesByItself(board: LudoBoard, die: Int) -> Bool {
        board.legalChoices(die: die) == [.pass]
    }

    /// The saved roll, when it was rolled for this very position. A different
    /// game, game number or move count means the board moved on, so the roll is
    /// discarded.
    static func restoredDie(from saved: LudoSavedRoll?, at position: LudoPosition) -> Int? {
        guard let saved, saved.position == position, faces.contains(saved.die) else { return nil }
        return saved.die
    }

    /// The hint while the die waits on the person's tray.
    static func hintBeforeRoll(board: LudoBoard, moves: [Int], me: BoardPlayer) -> LudoHint? {
        let movers = LudoBoard.movers(moves) ?? []
        if movers.last == me {
            return board.missedSixes > 0 ? .triesLeft(LudoBoard.triesInBase - board.missedSixes) : .rollAgain
        }
        if !movers.contains(me) {
            return .swipeToRoll
        }
        let allInBase = (0..<LudoBoard.pawnsPerPlayer).allSatisfy {
            board.progress[LudoBoard.pawnIndex(me, $0)] == 0
        }
        return allInBase ? .rollSix : nil
    }

    /// The hint once the die has landed. Only a pass has one.
    static func hintAfterRoll(board: LudoBoard, die: Int) -> LudoHint? {
        passesByItself(board: board, die: die) ? .noMove(die: die) : nil
    }
}
