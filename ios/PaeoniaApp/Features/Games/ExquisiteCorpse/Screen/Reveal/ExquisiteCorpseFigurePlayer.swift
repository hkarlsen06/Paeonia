import Observation
import PencilKit
import QuartzCore

/// Plays the strokes of the three parts of one figure. Each part has its own
/// `GameReplayTimeline` and `GameReplayClock`. A part that has not
/// started shows nothing, the part that plays shows the strokes drawn so far, and
/// a part that finished shows all of them.
///
/// A part plays at its own pace, or faster so it takes at most
/// `ExquisiteCorpseRevealTimeline.longestReplay`. Holding the screen plays the
/// part at 4x on top of that.
///
/// The player runs no timers. The replay canvas of each part asks `isFinished`
/// on every screen frame, and the first time it answers yes the player calls
/// `onPartFinished`, so the reveal can open the next fold. The reveal timeline
/// and the "Our creatures" detail screen both use it.
@MainActor
@Observable
final class ExquisiteCorpseFigurePlayer {
    typealias Part = ExquisiteCorpsePartKind

    /// The part whose strokes are being drawn. Nil between parts.
    private(set) var playingPart: Part?
    private(set) var isFastForwarding = false
    /// Goes up each time `reset` blanks the parts. The view gives its canvases
    /// this id, so they start empty.
    private(set) var generation = 0

    /// Called once each time a part's replay reaches its end, never after `finish`.
    @ObservationIgnored var onPartFinished: (@MainActor (Part) -> Void)?

    private struct Track {
        let timeline: GameReplayTimeline
        /// Nil while the part waits for its turn.
        var clock: GameReplayClock?
        /// The rate that fits the part into the longest replay, before any hold.
        var baseRate = 1.0
        var hasReported = false
    }

    @ObservationIgnored private var tracks: [Part: Track] = [:]
    /// `playInSequence` is running, so each finished part starts the next one.
    @ObservationIgnored private var isPlayingInSequence = false
    @ObservationIgnored private let monotonicNow: @Sendable () -> TimeInterval
    @ObservationIgnored private let selection: @MainActor () -> Void

    init(
        monotonicNow: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() },
        selection: @escaping @MainActor () -> Void = {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.6)
        }
    ) {
        self.monotonicNow = monotonicNow
        self.selection = selection
    }

    var isPlaying: Bool { playingPart != nil }

    // MARK: Loading

    /// Takes the drawings at the canonical side. Every part waits for its turn.
    func load(_ drawings: [Part: PKDrawing]) {
        tracks = drawings.mapValues { Track(timeline: GameReplayTimeline(drawing: $0)) }
        playingPart = nil
        isPlayingInSequence = false
    }

    // MARK: Playing

    /// Starts the replay of `part` from its first stroke. An empty drawing is
    /// finished at once and reported before this returns.
    func start(_ part: Part) {
        guard var track = tracks[part] else { return }
        track.baseRate = ExquisiteCorpseRevealTimeline.replayRate(duration: track.timeline.duration)
        track.clock = GameReplayClock(
            duration: track.timeline.duration,
            replayTime: 0,
            rate: track.baseRate * speedFactor,
            at: monotonicNow()
        )
        track.hasReported = false
        tracks[part] = track
        playingPart = part
        if track.timeline.duration <= 0 {
            reportFinished(part)
        }
    }

    /// Hold to play at 4x on top of the part's own rate, release to go back. The
    /// haptic fires once per press. The speed carries over to the next part while
    /// the hold lasts.
    func setFastForward(_ isOn: Bool) {
        guard isOn != isFastForwarding else { return }
        isFastForwarding = isOn
        if isOn {
            selection()
        }
        guard let part = playingPart, var track = tracks[part], var clock = track.clock else { return }
        clock.setRate(track.baseRate * speedFactor, at: monotonicNow())
        track.clock = clock
        tracks[part] = track
    }

    /// Shows every part in full at once, for a tap, Reduce Motion and "Show the
    /// whole figure". Nothing is reported.
    func finish() {
        let wall = monotonicNow()
        for (part, var track) in tracks {
            var clock = track.clock ?? GameReplayClock(duration: track.timeline.duration, startingAt: wall)
            clock.finish(at: wall)
            track.clock = clock
            track.hasReported = true
            tracks[part] = track
        }
        playingPart = nil
        isFastForwarding = false
        isPlayingInSequence = false
    }

    /// Blanks every part so each one waits for its turn again.
    func reset() {
        for part in tracks.keys {
            tracks[part]?.clock = nil
            tracks[part]?.hasReported = false
        }
        playingPart = nil
        isPlayingInSequence = false
        generation += 1
    }

    /// Plays the head, the body and the legs one after the other, with no folds.
    /// For Reduce Motion and the "Play again" actions.
    func playInSequence() {
        reset()
        isPlayingInSequence = true
        start(.head)
    }

    // MARK: Frames

    /// What `GameReplaySurface` draws for `part` on each screen frame.
    func frames(for part: Part) -> GameReplayFrames {
        GameReplayFrames(
            drawing: { [weak self] wall, side in self?.drawing(for: part, atWall: wall, side: side) },
            isFinished: { [weak self] wall in self?.isFinished(part, atWall: wall) ?? false }
        )
    }

    /// The part as it looks at `wall` (a steady clock such as `CACurrentMediaTime()`),
    /// scaled to a canvas of `side` points. Nil while the part waits for its turn
    /// or is not loaded.
    func drawing(for part: Part, atWall wall: TimeInterval, side: CGFloat) -> PKDrawing? {
        guard let track = tracks[part], let clock = track.clock else { return nil }
        return GameCanvas.fitted(track.timeline.drawing(at: clock.replayTime(at: wall)), toSide: side)
    }

    /// True once every stroke of the part is drawn. The first time it is true
    /// after a start, the player reports the part as finished.
    func isFinished(_ part: Part, atWall wall: TimeInterval) -> Bool {
        guard let clock = tracks[part]?.clock, clock.isFinished(at: wall) else { return false }
        reportFinished(part)
        return true
    }

    // MARK: Private

    private var speedFactor: Double {
        isFastForwarding ? GameReplayClock.fastForwardRate : 1
    }

    private func reportFinished(_ part: Part) {
        guard var track = tracks[part], !track.hasReported else { return }
        track.hasReported = true
        tracks[part] = track
        if playingPart == part {
            playingPart = nil
        }
        if isPlayingInSequence {
            if let next = part.next {
                start(next)
            } else {
                isPlayingInSequence = false
            }
        }
        onPartFinished?(part)
    }
}
