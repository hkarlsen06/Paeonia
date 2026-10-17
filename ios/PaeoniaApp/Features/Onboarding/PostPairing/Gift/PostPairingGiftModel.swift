import Observation
import QuartzCore

/// The haptics and sounds the gift replay plays. Injected so tests can record them.
struct PostPairingGiftEffects {
    /// A stroke of the partner's drawing just finished.
    var strokeFinished: @MainActor () -> Void
    /// The last stroke landed.
    var replayFinished: @MainActor () -> Void

    static let live = PostPairingGiftEffects(
        strokeFinished: {
            PaeoniaHaptics.streakTick(intensity: 0.3)
            GameSound.tick.play(volume: 0.25)
        },
        replayFinished: {
            PaeoniaHaptics.giftReplayFinished()
            GameSound.chime.play(volume: 0.8)
        }
    )
}

/// The partner's drawing as a wrapped gift: it waits to be opened, then plays back
/// stroke by stroke at the pace it was drawn, with a soft tick as each stroke lands.
/// Holding speeds it up, as in Draw & Guess.
@MainActor
@Observable
final class PostPairingGiftModel {
    enum Phase: Equatable {
        case wrapped
        /// The envelope is opening. The view runs that part.
        case opening
        case replaying
        case finished
    }

    private(set) var phase: Phase = .wrapped
    private(set) var isFastForwarding = false

    @ObservationIgnored private let timeline: GameReplayTimeline
    @ObservationIgnored private let effects: PostPairingGiftEffects
    @ObservationIgnored private let monotonicNow: @Sendable () -> TimeInterval
    @ObservationIgnored private var clock: GameReplayClock?
    @ObservationIgnored private var playTask: Task<Void, Never>?

    /// Ticks closer together than this are dropped, so fast drawing or fast-forward
    /// never turns into a buzz.
    private static let minimumTickGap: TimeInterval = 0.12
    private static let pollInterval: Duration = .milliseconds(40)

    init(
        gift: PostPairingGift,
        effects: PostPairingGiftEffects = .live,
        monotonicNow: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        timeline = GameReplayTimeline(drawing: gift.drawing)
        self.effects = effects
        self.monotonicNow = monotonicNow
    }

    /// Returns false when the gift was already opened.
    func beginOpening() -> Bool {
        guard phase == .wrapped else {
            return false
        }
        phase = .opening
        return true
    }

    /// Plays the drawing. With `showsAtOnce` (Reduce Motion) the finished drawing
    /// shows right away.
    func startReplay(showsAtOnce: Bool) {
        guard phase == .opening else {
            return
        }
        let wall = monotonicNow()
        var fresh = GameReplayClock(duration: timeline.duration, startingAt: wall)
        if showsAtOnce {
            fresh.finish(at: wall)
        }
        clock = fresh
        phase = .replaying
        playTask = Task { [weak self] in
            await self?.play()
        }
    }

    /// Hold to speed up, release to go back to the drawn pace.
    func setFastForward(_ isOn: Bool) {
        guard phase == .replaying, var clock, isFastForwarding != isOn else {
            return
        }
        clock.setRate(isOn ? GameReplayClock.fastForwardRate : 1, at: monotonicNow())
        self.clock = clock
        isFastForwarding = isOn
    }

    /// "Show the whole drawing" for VoiceOver.
    func showWholeDrawing() {
        guard phase == .replaying, var clock else {
            return
        }
        clock.finish(at: monotonicNow())
        self.clock = clock
        isFastForwarding = false
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
    }

    /// What `GameReplaySurface` draws on each screen frame.
    var frames: GameReplayFrames {
        GameReplayFrames(
            playback: { [weak self] wall in
                guard let self, let clock else { return nil }
                return .init(timeline: timeline, time: clock.replayTime(at: wall))
            },
            isFinished: { [weak self] wall in self?.clock?.isFinished(at: wall) ?? false }
        )
    }

    /// Follows the clock until the drawing is done, ticking as strokes land.
    private func play() async {
        var landedCount = 0
        var lastTick = -TimeInterval.infinity
        while !Task.isCancelled, let clock {
            let wall = monotonicNow()
            if clock.isFinished(at: wall) {
                finish()
                return
            }
            let time = clock.replayTime(at: wall)
            let landed = timeline.items.reduce(0) { $1.end <= time ? $0 + 1 : $0 }
            if landed > landedCount {
                landedCount = landed
                if wall - lastTick >= Self.minimumTickGap {
                    lastTick = wall
                    effects.strokeFinished()
                }
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func finish() {
        isFastForwarding = false
        phase = .finished
        effects.replayFinished()
    }
}
