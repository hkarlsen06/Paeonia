import CoreGraphics
import Foundation

/// The camera of the Ultimate Tic-Tac-Toe board. It shows the whole board
/// unless the player pinches out over a small board to look at it closely.
/// Pure, so the rule reads without a screen.
nonisolated enum UltimateTicTacToeZoom {
    /// A pinch-in smaller than this zooms back out.
    static let pinchInThreshold: CGFloat = 0.85
    /// A spread larger than this zooms into the small board under the fingers.
    static let spreadThreshold: CGFloat = 1.15

    /// The small board the camera shows after a pinch that has reached
    /// `magnification`, or nil for the whole board. `start` is where the
    /// fingers first touched, in board coordinates.
    static func focus(
        afterPinch magnification: CGFloat,
        from focus: Int?,
        startingAt start: CGPoint,
        geometry: UltimateTicTacToeBoardGeometry
    ) -> Int? {
        if focus == nil, magnification > spreadThreshold {
            return geometry.nearestBoard(to: start)
        }
        if focus != nil, magnification < pinchInThreshold {
            return nil
        }
        return focus
    }
}

/// How long each beat of a move takes, in seconds.
nonisolated enum UltimateTicTacToeTiming {
    /// My partner's mark draws in.
    static let markDraw: TimeInterval = 0.4
    /// My own mark pops in before anything else moves.
    static let minePop: TimeInterval = 0.2
    /// A small board closes: the strike line, the fade and the big mark.
    static let close: TimeInterval = 0.45
    static let afterClose: TimeInterval = 0.15
    /// The spark flies from the cell just played to the board it sends the
    /// next player to.
    static let spark: TimeInterval = 0.45
    /// The whole board shows as this phone left it before missed moves play.
    static let openLeadIn = Duration.milliseconds(600)

    /// How long the beat of `event` takes on `board`, the board that holds it:
    /// the mark comes in, a small board it closed closes, and the spark flies
    /// when the next player is sent to one board.
    static func beat(of event: BoardMoveEvent, on board: UltimateTicTacToeBoard) -> TimeInterval {
        var seconds = event.isMine ? minePop : markDraw
        if board.boards.indices.contains(event.move / 9), board.boards[event.move / 9] != .open {
            seconds += close + (board.outcome == nil ? afterClose : 0)
        }
        if board.outcome == nil, board.forced != nil {
            seconds += spark
        }
        return seconds
    }
}
