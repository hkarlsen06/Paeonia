import PencilKit
import UIKit

/// What a replay surface draws on each screen frame.
struct GameReplayFrames {
    /// The drawing at a wall time, scaled to `side`. Nil while there is nothing to play.
    let drawing: @MainActor (_ wall: TimeInterval, _ side: CGFloat) -> PKDrawing?
    let isFinished: @MainActor (_ wall: TimeInterval) -> Bool
}
