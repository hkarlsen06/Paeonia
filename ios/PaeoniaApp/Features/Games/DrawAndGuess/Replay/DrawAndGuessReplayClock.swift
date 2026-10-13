import Foundation

/// Maps wall time to replay time. Changing the rate (hold to fast-forward)
/// re-anchors the clock at the current replay time, so the picture never jumps.
/// Pass any steady wall clock, such as `CACurrentMediaTime()`.
nonisolated struct DrawAndGuessReplayClock: Equatable, Sendable {
    static let fastForwardRate: Double = 4

    let duration: TimeInterval
    private(set) var rate: Double = 1
    private var anchorWall: TimeInterval
    private var anchorReplay: TimeInterval = 0

    /// Starts playing at replay time 0 when the wall clock reads `wall`.
    init(duration: TimeInterval, startingAt wall: TimeInterval) {
        self.duration = duration
        anchorWall = wall
    }

    /// Plays on from `replayTime` at `rate` when the wall clock reads `wall`, as
    /// the partner's replay does on their phone.
    init(duration: TimeInterval, replayTime: TimeInterval, rate: Double, at wall: TimeInterval) {
        self.duration = duration
        anchorWall = wall
        anchorReplay = min(duration, max(0, replayTime))
        self.rate = max(0, rate)
    }

    func replayTime(at wall: TimeInterval) -> TimeInterval {
        min(duration, max(0, anchorReplay + (wall - anchorWall) * rate))
    }

    func isFinished(at wall: TimeInterval) -> Bool {
        replayTime(at: wall) >= duration
    }

    /// Changes the speed from `wall` on. 1 is the drawn pace and 0 pauses.
    mutating func setRate(_ newRate: Double, at wall: TimeInterval) {
        anchorReplay = replayTime(at: wall)
        anchorWall = wall
        rate = max(0, newRate)
    }

    /// Jumps to the end, for the reveal.
    mutating func finish(at wall: TimeInterval) {
        anchorReplay = duration
        anchorWall = wall
    }
}
