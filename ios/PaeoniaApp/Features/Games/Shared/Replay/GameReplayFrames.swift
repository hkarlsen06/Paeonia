import PencilKit
import UIKit

/// What a replay surface draws on each screen frame.
struct GameReplayFrames {
    /// Where a replay is at a wall time: the timeline in canonical size, and the
    /// replay time in it.
    struct Playback {
        let timeline: GameReplayTimeline
        let time: TimeInterval
    }

    /// Nil while there is nothing to play.
    let playback: @MainActor (_ wall: TimeInterval) -> Playback?
    let isFinished: @MainActor (_ wall: TimeInterval) -> Bool
}
