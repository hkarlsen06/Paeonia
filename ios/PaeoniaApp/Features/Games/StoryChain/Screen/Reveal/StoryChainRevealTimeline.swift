import Foundation
import SwiftUI

/// Runs the reveal of a finished story and owns every value the screen draws
/// from it. The screen calls `begin` once. The steps then play on a schedule, or
/// the settled state shows at once (Reduce Motion, or a tap).
///
/// What the screen does with each value:
/// - `scrolledToTop`: fade the bottom out and scroll the page to the top.
/// - `titleProgress`: pass it to `StoryChainTitleText`. `titleShown` says the
///   title has started.
/// - `bylineShown`, `statsShown`, `actionsShown`: fade those rows up.
/// - `bloomStart`: pass it to `StoryChainTitleText`, so the petals burst from the title.
/// - `ornamentShown`: pass it to `StoryChainOrnament`.
///
/// Every run has an id, and each step checks it after sleeping, so no step or
/// haptic can happen after the timeline settled or stopped. The schedule, the
/// haptics, the clock and the sleep are injected, so tests run it fast.
@MainActor
@Observable
final class StoryChainRevealTimeline {
    typealias Schedule = StoryChainRevealSchedule
    typealias Haptics = StoryChainRevealHaptics
    typealias Event = StoryChainRevealEvent
    typealias Step = StoryChainRevealStep

    // MARK: State the screen draws

    /// The page scrolls to the top and the bottom fades out.
    private(set) var scrolledToTop = false
    private(set) var titleShown = false
    /// How much of the title has written itself in, from 0 to 1. It changes inside
    /// a linear animation, so `StoryChainTitleText` follows it frame by frame.
    private(set) var titleProgress: Double = 0
    private(set) var bylineShown = false
    private(set) var ornamentShown = false
    /// When the petals burst, or nil before the burst and when the reveal settled
    /// without playing.
    private(set) var bloomStart: Date?
    private(set) var statsShown = false
    /// The star and the button.
    private(set) var actionsShown = false
    private(set) var isSettled = false
    /// The settled state was shown without playing, so nothing should animate.
    private(set) var wasSkipped = false
    /// The story being revealed. The bloom uses it as its seed.
    private(set) var storyID: UUID?

    @ObservationIgnored private let schedule: Schedule
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        schedule: Schedule = .standard,
        haptics: Haptics? = nil,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.schedule = schedule
        self.haptics = haptics ?? .live
        self.now = now
        self.sleep = sleep
    }

    var hasBegun: Bool { storyID != nil }

    /// True while a tap can still end the reveal early.
    var canSkip: Bool { hasBegun && !isSettled }

    // MARK: Entry points

    /// Starts the reveal. Later calls do nothing, until `reset`.
    func begin(storyID: UUID, reduceMotion: Bool) {
        guard self.storyID == nil else { return }
        self.storyID = storyID
        if reduceMotion {
            applySettledState()
            haptics.answerRevealed()
            return
        }
        runID += 1
        let id = runID
        let steps = Self.steps(schedule: schedule)
        task = Task { [weak self] in
            await self?.run(steps, id: id)
        }
    }

    /// Jumps to the settled state without repeating haptics.
    func skip() {
        guard canSkip else { return }
        cancelRun()
        withAnimation(PaeoniaMotion.stateChange) {
            applySettledState()
        }
    }

    /// Ends the run when the view goes away.
    func stop() {
        guard canSkip else { return }
        cancelRun()
        applySettledState()
    }

    /// Clears the reveal and stops its run, so another story can play it.
    func reset() {
        cancelRun()
        storyID = nil
        scrolledToTop = false
        titleShown = false
        titleProgress = 0
        bylineShown = false
        ornamentShown = false
        bloomStart = nil
        statsShown = false
        actionsShown = false
        isSettled = false
        wasSkipped = false
    }

    // MARK: Script

    /// The beats of the reveal in order. Pure, so tests read the script itself.
    nonisolated static func steps(schedule: Schedule) -> [Step] {
        StoryChainRevealScript.steps(schedule: schedule)
    }

    private func run(_ steps: [Step], id: Int) async {
        var elapsed: TimeInterval = 0
        for step in steps {
            let wait = step.at - elapsed
            if wait > 0 {
                try? await sleep(.seconds(wait))
                elapsed = step.at
            }
            guard id == runID, !Task.isCancelled else { return }
            apply(step.event)
        }
        guard id == runID, !Task.isCancelled else { return }
        isSettled = true
    }

    private func apply(_ event: Event) {
        switch event {
        case .scrollTop:
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                scrolledToTop = true
            }
        case .title:
            haptics.selection()
            titleShown = true
            withAnimation(.linear(duration: schedule.titleDuration)) {
                titleProgress = 1
            }
        case .bloom:
            bloomStart = now()
            haptics.answerRevealed()
        case .byline:
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                bylineShown = true
            }
        case .ornament:
            withAnimation(PaeoniaMotion.celebrationReveal) {
                ornamentShown = true
            }
        case .stats:
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                statsShown = true
            }
        case .actions:
            withAnimation(PaeoniaMotion.cardReveal) {
                actionsShown = true
            }
        }
    }

    private func applySettledState() {
        scrolledToTop = true
        titleShown = true
        titleProgress = 1
        bylineShown = true
        ornamentShown = true
        bloomStart = nil
        statsShown = true
        actionsShown = true
        wasSkipped = true
        isSettled = true
    }

    private func cancelRun() {
        runID += 1
        task?.cancel()
        task = nil
    }
}
