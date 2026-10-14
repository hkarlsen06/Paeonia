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
    case tapToRoll
    /// Every pawn of the person waits in the base.
    case rollSix
    /// The last move earned another roll.
    case rollAgain
    /// The roll left no pawn to move, so the turn passes by itself.
    case noMove(die: Int)
}

extension LudoHint {
    var text: LocalizedStringResource {
        switch self {
        case .tapToRoll: .ludoHintTapToRoll
        case .rollSix: .ludoHintRollSix
        case .rollAgain: .ludoHintRollAgain
        case let .noMove(die): .ludoHintNoMove(die)
        }
    }
}

/// What the screen does with a roll once the die has landed.
nonisolated enum LudoAutomaticMove: Equatable, Sendable {
    /// The only option, played after the delay.
    case move(LudoChoice, after: Duration)
    /// No pawn can move, so the turn passes after the delay.
    case pass(after: Duration)
}

/// The decisions behind the roll, with no view, clock or storage, so tests can
/// check them directly.
nonisolated enum LudoRollDecision {
    /// How long the only option waits before it moves by itself.
    static let autoMoveDelay: Duration = .milliseconds(500)
    /// How long a pass waits, while the status says "No move with a 3".
    static let autoPassDelay: Duration = .milliseconds(1_200)

    static let faces = 1...LudoBoard.dieFaces

    /// The choices that give a different board. Two pawns in the base, or two
    /// pawns on one square, give the same result, so only the first of them
    /// counts.
    static func distinctChoices(board: LudoBoard, die: Int) -> [LudoChoice] {
        var seen: [[[Int]]] = []
        var kept: [LudoChoice] = []
        for choice in board.legalChoices(die: die) {
            guard let result = resultingPawns(board: board, die: die, choice: choice) else { continue }
            if !seen.contains(result) {
                seen.append(result)
                kept.append(choice)
            }
        }
        return kept
    }

    /// Each player's pawn progress after the move, in order of progress, so two
    /// pawns that swap places look the same.
    private static func resultingPawns(board: LudoBoard, die: Int, choice: LudoChoice) -> [[Int]]? {
        guard let after = board.applying(LudoBoard.move(die: die, choice: choice)) else { return nil }
        return [BoardPlayer.one, .two].map { player in
            (0..<LudoBoard.pawnsPerPlayer)
                .map { after.progress[LudoBoard.pawnIndex(player, $0)] }
                .sorted()
        }
    }

    /// The move the screen plays by itself after the die lands, or nil when the
    /// person has a choice to make.
    static func automaticMove(board: LudoBoard, die: Int) -> LudoAutomaticMove? {
        let options = distinctChoices(board: board, die: die)
        guard options.count == 1, let only = options.first else { return nil }
        return only == .pass ? .pass(after: autoPassDelay) : .move(only, after: autoMoveDelay)
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
            return .rollAgain
        }
        if !movers.contains(me) {
            return .tapToRoll
        }
        let allInBase = (0..<LudoBoard.pawnsPerPlayer).allSatisfy {
            board.progress[LudoBoard.pawnIndex(me, $0)] == 0
        }
        return allInBase ? .rollSix : nil
    }

    /// The hint once the die has landed. Only a pass has one.
    static func hintAfterRoll(board: LudoBoard, die: Int) -> LudoHint? {
        distinctChoices(board: board, die: die) == [.pass] ? .noMove(die: die) : nil
    }
}
