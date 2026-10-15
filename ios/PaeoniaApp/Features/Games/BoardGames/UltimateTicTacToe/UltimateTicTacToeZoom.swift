import CoreGraphics
import Foundation

/// Decides which small board the Ultimate Tic-Tac-Toe view fills the screen
/// with, and what a tap means. The view and the playback only carry out its
/// answers, so the rules read and test without a screen.
nonisolated struct UltimateTicTacToeZoom: Equatable {
    /// What the player asked for since the last move or turn change.
    enum Choice: Equatable {
        /// Follow the game: zoom into the board I must play in.
        case automatic
        /// The player picked a board to play in.
        case board(Int)
        /// The player zoomed back out to look at the whole board.
        case wholeBoard
    }

    /// What a tap on the board does.
    enum Tap: Equatable {
        /// Zoom into this small board.
        case focus(Int)
        /// Play this move.
        case play(Int)
        case zoomOut
        case ignore
    }

    /// A pinch-in smaller than this zooms back out.
    static let pinchThreshold: CGFloat = 0.85

    var board: UltimateTicTacToeBoard
    var canPlay: Bool
    /// False for VoiceOver, which never zooms.
    var zoomEnabled: Bool
    var choice = Choice.automatic

    /// The small board to fill the view with while nothing is moving, or nil for
    /// the whole board. Only my own turn zooms. A board I must play in zooms in
    /// by itself. When I may choose, the whole board shows until I pick one.
    var restingFocus: Int? {
        guard zoomEnabled, canPlay, board.outcome == nil else { return nil }
        switch choice {
        case .wholeBoard:
            return nil
        case .board(let chosen) where board.openBoards.contains(chosen):
            return chosen
        case .automatic, .board:
            return board.forced
        }
    }

    /// The meaning of a tap at `point`, given in board coordinates, while the
    /// view is focused on `focus`.
    func tap(at point: CGPoint, geometry: UltimateTicTacToeBoardGeometry, focus: Int?) -> Tap {
        guard board.outcome == nil else { return .ignore }
        guard zoomEnabled else {
            return play(geometry.move(at: point))
        }
        if let focus {
            guard geometry.smallRect(focus).contains(point) else { return .zoomOut }
            return play(UltimateTicTacToeBoard.move(board: focus, cell: geometry.cell(in: focus, at: point)))
        }
        let tapped = geometry.nearestBoard(to: point)
        return canPlay && board.openBoards.contains(tapped) ? .focus(tapped) : .ignore
    }

    static func isZoomOutPinch(_ magnification: CGFloat) -> Bool {
        magnification < pinchThreshold
    }

    private func play(_ move: Int) -> Tap {
        canPlay && board.isLegal(move) ? .play(move) : .ignore
    }
}

/// How long each beat of a move takes, in seconds.
nonisolated enum UltimateTicTacToeTiming {
    /// The camera moves to the board my partner played in.
    static let zoomToMove: TimeInterval = 0.35
    /// My partner's mark draws in.
    static let markDraw: TimeInterval = 0.4
    /// The board rests on my partner's move before it moves on.
    static let hold: TimeInterval = 0.35
    /// My own mark pops in before the camera leaves it.
    static let minePop: TimeInterval = 0.2
    /// A small board closes: the strike line, the fade and the big mark.
    static let close: TimeInterval = 0.45
    static let afterClose: TimeInterval = 0.15
    /// The camera glides to where the next move is played.
    static let regroup: TimeInterval = 0.5
    /// On a trip between two small boards, how long the camera heads out per
    /// board it crosses before it turns to the new board.
    static let pullBack: TimeInterval = 0.08
    /// The board my partner is sent to pulses once the camera is nearly out.
    static let pulseDelay: TimeInterval = 0.4
    static let pulse: TimeInterval = 0.35
    /// The pause before the opening zoom into the board I must play in.
    static let intro: TimeInterval = 0.4

    /// How long the board takes to show one of my moves, for the screen's replay.
    static let mine = Duration.milliseconds(900)
    /// How long the board takes to show one of my partner's moves. In a replay
    /// the camera comes from the last move's board, so it pulls back on the way.
    static let partner = Duration.milliseconds(1_180)
}
