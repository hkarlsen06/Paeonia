import CoreGraphics

/// What I have picked on my turn, before I lock it in.
nonisolated enum UltimateTicTacToePick: Equatable {
    case none
    /// Free choice: a board is picked, no cell yet.
    case board(Int)
    /// A cell is picked and waits for "Lock in". The move index 0..<81.
    case move(Int)

    /// What a tap on the board does.
    enum Tap: Equatable {
        /// The pick becomes this.
        case pick(UltimateTicTacToePick)
        /// Back to the whole board, after a tap outside the small board the
        /// camera shows.
        case zoomOut
        case ignore
    }

    /// The small board I play in: the one I was sent to, or the open board I
    /// picked when I may choose. Nil while I may choose and have not picked.
    func playingBoard(on board: UltimateTicTacToeBoard) -> Int? {
        if let forced = board.forced {
            return forced
        }
        let picked: Int? = switch self {
        case .none: nil
        case .board(let index): index
        case .move(let move): move / 9
        }
        return picked.flatMap { board.openBoards.contains($0) ? $0 : nil }
    }

    /// The picked move, while it is still legal on `board`. "Lock in" plays it.
    func move(on board: UltimateTicTacToeBoard) -> Int? {
        if case .move(let move) = self, board.isLegal(move) { move } else { nil }
    }

    /// True while I may play in any open board and have not picked one, so the
    /// status row asks me to choose.
    func asksForBoard(on board: UltimateTicTacToeBoard, canPlay: Bool) -> Bool {
        canPlay && playingBoard(on: board) == nil
    }

    /// The meaning of a tap at `point`, in board coordinates, while the camera
    /// shows `focus`. Each small board owns the area up to the middle of its
    /// gaps, and a tap in the board I play in picks its nearest cell.
    func tap(
        at point: CGPoint,
        on board: UltimateTicTacToeBoard,
        canPlay: Bool,
        geometry: UltimateTicTacToeBoardGeometry,
        focus: Int?
    ) -> Tap {
        if let focus, !geometry.smallRect(focus).contains(point) {
            return .zoomOut
        }
        guard canPlay else { return .ignore }
        let tapped = geometry.nearestBoard(to: point)
        let next: UltimateTicTacToePick
        if tapped == playingBoard(on: board) {
            let move = UltimateTicTacToeBoard.move(board: tapped, cell: geometry.cell(in: tapped, at: point))
            guard board.isLegal(move) else { return .ignore }
            next = .move(move)
        } else if board.forced == nil, board.openBoards.contains(tapped) {
            next = .board(tapped)
        } else {
            return .ignore
        }
        return next == self ? .ignore : .pick(next)
    }
}
