import Foundation

nonisolated extension UltimateTicTacToeBoard.SmallBoard {
    var isWon: Bool {
        if case .won = self { true } else { false }
    }
}

/// What a move that is still arriving holds back, so its beat can play. The
/// board already contains the move. The view draws it only once the hold lifts.
nonisolated struct UltimateTicTacToeHold: Equatable {
    /// My partner's mark, hidden until it draws in.
    var hiddenMove: Int?
    /// A small board this move closed. It shows as open until its closing beat.
    var unclosedBoard: Int?

    static let none = UltimateTicTacToeHold()

    /// What `event` holds back on `board`, or nil when the board does not hold
    /// the move. My own mark is never hidden, because it pops in at once.
    static func arriving(_ event: BoardMoveEvent, on board: UltimateTicTacToeBoard) -> UltimateTicTacToeHold? {
        guard board.cells.indices.contains(event.move), board.cells[event.move] == event.player else { return nil }
        let index = event.move / 9
        return UltimateTicTacToeHold(
            hiddenMove: event.isMine ? nil : event.move,
            unclosedBoard: board.boards[index] == .open ? nil : index
        )
    }

    /// The hold of a move the playback has not started yet. The view uses it
    /// while it draws the new board, before the playback hears about the move,
    /// so a mark never flashes on before its beat.
    static func pending(
        lastMove: BoardMoveEvent?,
        handled: Int?,
        board: UltimateTicTacToeBoard,
        enabled: Bool
    ) -> UltimateTicTacToeHold? {
        guard enabled, let lastMove, lastMove.number != handled else { return nil }
        return arriving(lastMove, on: board)
    }

    func isHolding(_ board: Int) -> Bool {
        unclosedBoard == board || hiddenMove.map { $0 / 9 } == board
    }
}

/// One small board as it is drawn right now.
nonisolated struct UltimateTicTacToeSmallBoardContent: Equatable {
    /// The nine cells in row order. A held back mark reads as empty.
    let cells: [BoardPlayer?]
    let state: UltimateTicTacToeBoard.SmallBoard
    /// The three cells of the winning line as 0 to 8. Empty unless the board is won.
    let winningCells: [Int]

    init(board: UltimateTicTacToeBoard, index: Int, hold: UltimateTicTacToeHold) {
        let first = index * 9
        let presented: UltimateTicTacToeBoard.SmallBoard = hold.unclosedBoard == index ? .open : board.boards[index]
        cells = (0..<9).map { hold.hiddenMove == first + $0 ? nil : board.cells[first + $0] }
        state = presented
        winningCells = presented.isWon ? board.winningCells(of: index).map { $0 - first } : []
    }
}

/// How bright a small board is and whether it glows.
nonisolated struct UltimateTicTacToeEmphasis: Equatable {
    enum Glow: Equatable {
        case none
        /// The color of the player who moves next.
        case next
        /// The color of the player who won the game.
        case winner
    }

    var glow: Glow
    var opacity: Double

    static let plain = UltimateTicTacToeEmphasis(glow: .none, opacity: 1)
}

/// The three beats of the outcome highlight that change what the board draws.
nonisolated struct UltimateTicTacToeOutcomeState: Equatable {
    /// The boards outside the winning line dim to 40%.
    var isDimmed = false
    /// How many boards of the winning line have lit up, in order.
    var litCount = 0
    /// How much of the line through the winning boards is drawn.
    var lineProgress: CGFloat = 0
    /// After a draw, how bright the whole board is.
    var drawOpacity = 1.0
    /// The small board the last move won. The winning boards light up from it,
    /// and the line draws from it. Nil lights them in order.
    var origin: Int?

    static let idle = UltimateTicTacToeOutcomeState()
    static let restOpacity = 0.4
    static let drawSettledOpacity = 0.8

    /// The highlight once it has finished playing.
    static func settled(for outcome: BoardOutcome?) -> UltimateTicTacToeOutcomeState {
        guard let outcome else { return .idle }
        guard outcome.winner != nil else {
            return UltimateTicTacToeOutcomeState(drawOpacity: drawSettledOpacity)
        }
        return UltimateTicTacToeOutcomeState(isDimmed: true, litCount: outcome.line.count, lineProgress: 1)
    }

    /// The lines of three small boards the winner holds. One move can finish
    /// two lines, and then the outcome lists five boards.
    static func winningRows(of outcome: BoardOutcome) -> [[Int]] {
        let boards = Set(outcome.line)
        return UltimateTicTacToeBoard.winningLines.filter { boards.isSuperset(of: $0) }
    }

    /// The winning boards in the order they light up, nearest `origin` first.
    func litOrder(of outcome: BoardOutcome) -> [Int] {
        guard let origin else { return outcome.line }
        return outcome.line.sorted { Self.steps($0, origin) < Self.steps($1, origin) }
    }

    /// A winning row that starts at the end nearer `origin`.
    func fromOrigin(_ row: [Int]) -> [Int] {
        guard let origin, let first = row.first, let last = row.last,
              Self.steps(last, origin) < Self.steps(first, origin) else { return row }
        return row.reversed()
    }

    /// How many boards apart two small boards are along a row, a column or a diagonal.
    private static func steps(_ board: Int, _ other: Int) -> Int {
        max(abs(board / 3 - other / 3), abs(board % 3 - other % 3))
    }
}

/// Everything the board draws, as plain values. The view reads one of these per
/// small board.
nonisolated struct UltimateTicTacToeLook: Equatable {
    static let unusableOpacity = 0.7

    let board: UltimateTicTacToeBoard
    let hold: UltimateTicTacToeHold
    let focus: Int?
    /// No glow and no dimming while my partner's move plays, so the board
    /// stays calm until the camera moves on.
    let glowHeld: Bool
    let outcome: UltimateTicTacToeOutcomeState

    func content(of index: Int) -> UltimateTicTacToeSmallBoardContent {
        UltimateTicTacToeSmallBoardContent(board: board, index: index, hold: hold)
    }

    func emphasis(of index: Int) -> UltimateTicTacToeEmphasis {
        if let result = board.outcome {
            return emphasis(of: index, after: result)
        }
        guard !glowHeld else { return .plain }
        if board.openBoards.contains(index) {
            return UltimateTicTacToeEmphasis(glow: .next, opacity: 1)
        }
        let isOpen = hold.unclosedBoard == index || board.boards[index] == .open
        if isOpen, index != focus, !hold.isHolding(index) {
            return UltimateTicTacToeEmphasis(glow: .none, opacity: Self.unusableOpacity)
        }
        return .plain
    }

    private func emphasis(of index: Int, after result: BoardOutcome) -> UltimateTicTacToeEmphasis {
        guard result.winner != nil else {
            return UltimateTicTacToeEmphasis(glow: .none, opacity: outcome.drawOpacity)
        }
        guard outcome.isDimmed else { return .plain }
        if outcome.litOrder(of: result).prefix(outcome.litCount).contains(index) {
            return UltimateTicTacToeEmphasis(glow: .winner, opacity: 1)
        }
        if result.line.contains(index) {
            return .plain
        }
        return UltimateTicTacToeEmphasis(glow: .none, opacity: UltimateTicTacToeOutcomeState.restOpacity)
    }
}

/// The beats of the outcome highlight, measured from the moment the screen says
/// the outcome shows. Pure, so a test reads the script itself.
nonisolated enum UltimateTicTacToeOutcomeScript {
    enum Event: Equatable {
        /// The rest of the board dims.
        case dimRest
        /// The winning board at this position in the line lights up.
        case light(Int)
        case drawLine
        case bloom
        case clearBloom
        /// After a draw, everything dims.
        case dipDraw
        case settleDraw
    }

    struct Beat: Equatable {
        let at: TimeInterval
        let event: Event
    }

    static let lightStagger: TimeInterval = 0.1
    static let lineStart: TimeInterval = 0.15
    static let lineDuration: TimeInterval = 0.4
    static let bloomStart: TimeInterval = 0.55
    /// The petal bloom runs 0.9 s. The view drops it a little later.
    static let bloomLife: TimeInterval = 1.0
    static let drawSettle: TimeInterval = 0.6

    /// `lineCount` is the number of small boards in the winning line.
    static func beats(lineCount: Int, isDraw: Bool) -> [Beat] {
        if isDraw {
            return [Beat(at: 0, event: .dipDraw), Beat(at: drawSettle, event: .settleDraw)]
        }
        var beats = [Beat(at: 0, event: .dimRest)]
        beats += (0..<lineCount).map { Beat(at: lightStagger * Double($0), event: .light($0)) }
        beats.append(Beat(at: lineStart, event: .drawLine))
        beats.append(Beat(at: bloomStart, event: .bloom))
        beats.append(Beat(at: bloomStart + bloomLife, event: .clearBloom))
        return beats.sorted { $0.at < $1.at }
    }
}
