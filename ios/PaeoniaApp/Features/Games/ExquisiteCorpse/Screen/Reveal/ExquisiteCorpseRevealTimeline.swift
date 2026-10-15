import Foundation
import SwiftUI

/// Runs the reveal of a finished figure and owns every value the view draws
/// from it. The folded paper opens one fold at a time. The view replays each
/// part once its fold is open and tells the timeline when the replay ends, so
/// holding to speed up a part moves everything after it along. When the legs
/// are done the view zooms out to the whole figure.
///
/// Every step has a run id and checks it after sleeping, so no step or haptic
/// happens after the timeline settled or stopped. The schedule, the haptics and
/// the sleep are injected, so tests run it fast.
@MainActor
@Observable
final class ExquisiteCorpseRevealTimeline {
    typealias Part = ExquisiteCorpsePartKind

    enum Stage: Equatable {
        /// The paper is closed and shows its back.
        case folded
        /// The fold of the part is opening.
        case opening(Part)
        /// The part's fold is open and the view replays its strokes.
        case playing(Part)
        /// The legs are done and the view pulls back to the whole figure.
        case zoomingOut
        /// Everything shows.
        case settled
    }

    /// How long each beat waits, in seconds.
    nonisolated struct Schedule: Sendable {
        /// The closed paper sits before the first fold opens.
        var firstFold: TimeInterval = 0.3
        /// A fold takes this long to open, the length of `PaeoniaMotion.meaningfulMoment`.
        /// The replay starts and the haptic lands when it ends.
        var foldOpens: TimeInterval = 0.36
        /// From the end of a part's replay to the next fold opening.
        var betweenParts: TimeInterval = 0.3
        /// From the start of the zoom out to the haptic and the bloom.
        var zoomToBloom: TimeInterval = 0.3
        /// From the bloom to the title and the buttons.
        var bloomToTitle: TimeInterval = 0.6

        static let standard = Self()
    }

    /// The haptics and sounds of the reveal, injected so tests can record them.
    struct Haptics {
        var selection: @MainActor () -> Void
        var foldLanded: @MainActor (CGFloat) -> Void
        var answerRevealed: @MainActor () -> Void

        static let live = Self(
            selection: {
                PaeoniaHaptics.selection()
                GameSound.tap.play(volume: 0.6)
            },
            foldLanded: {
                PaeoniaHaptics.streakTick(intensity: $0)
                GameSound.fold.play(volume: 0.5 + 0.5 * $0)
            },
            answerRevealed: {
                PaeoniaHaptics.answerRevealed()
                GameSound.chime.play()
            }
        )
    }

    /// The longest a part's replay takes. A longer drawing plays faster to fit.
    nonisolated static let longestReplay: TimeInterval = 2.5

    /// How fast a part of `duration` replay seconds plays so it takes at most
    /// `longestReplay`. A short part plays at its own pace.
    nonisolated static func replayRate(duration: TimeInterval) -> Double {
        max(1, duration / longestReplay)
    }

    /// The strength of the haptic as the fold of `part` lands: it builds up.
    nonisolated static func foldIntensity(for part: Part) -> CGFloat {
        switch part {
        case .head: 0.4
        case .body: 0.6
        case .legs: 0.85
        }
    }

    // MARK: State the view draws

    private(set) var stage: Stage = .folded
    /// The parts whose fold has opened. A part stays open once it has.
    private(set) var openParts: Set<Part> = []
    /// The view shows the whole figure instead of the part that plays.
    private(set) var isZoomedOut = false
    /// The petals fly and the glow shows.
    private(set) var showsBloom = false
    private(set) var showsTitle = false
    private(set) var showsButtons = false

    /// `begin` was called and `reset` has not been since.
    private(set) var hasBegun = false

    var isSettled: Bool { stage == .settled }
    /// True while a tap can still end the reveal early.
    var canSkip: Bool { hasBegun && !isSettled }

    @ObservationIgnored private let schedule: Schedule
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// The part whose replay end the timeline waits for.
    @ObservationIgnored private var awaitedPart: Part?
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        schedule: Schedule = .standard,
        haptics: Haptics? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.schedule = schedule
        self.haptics = haptics ?? .live
        self.sleep = sleep
    }

    // MARK: Entry points

    /// Starts the reveal. Later calls do nothing. With Reduce Motion the whole
    /// figure shows at once, without folds, camera moves or bloom.
    func begin(reduceMotion: Bool) {
        guard !hasBegun else { return }
        hasBegun = true
        if reduceMotion {
            applySettledState()
            haptics.answerRevealed()
            return
        }
        haptics.selection()
        after(schedule.firstFold) { [self] in
            open(.head)
        }
    }

    /// The view finished replaying `part`, or it had nothing to replay. Anything
    /// but the part being played is ignored.
    func partReplayFinished(_ part: Part) {
        guard awaitedPart == part else { return }
        awaitedPart = nil
        guard let next = part.next else {
            zoomOut()
            return
        }
        after(schedule.betweenParts) { [self] in
            open(next)
        }
    }

    /// Jumps to the settled state without repeating haptics. A bloom that has
    /// started keeps showing, and one that has not never starts.
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

    /// Clears the reveal and stops its run, so it can play again.
    func reset() {
        cancelRun()
        hasBegun = false
        stage = .folded
        openParts = []
        isZoomedOut = false
        showsBloom = false
        showsTitle = false
        showsButtons = false
    }

    // MARK: Steps

    private func open(_ part: Part) {
        stage = .opening(part)
        withAnimation(PaeoniaMotion.meaningfulMoment) {
            _ = openParts.insert(part)
        }
        after(schedule.foldOpens) { [self] in
            haptics.foldLanded(Self.foldIntensity(for: part))
            stage = .playing(part)
            awaitedPart = part
        }
    }

    private func zoomOut() {
        stage = .zoomingOut
        withAnimation(PaeoniaMotion.celebrationReveal) {
            isZoomedOut = true
        }
        after(schedule.zoomToBloom) { [self] in
            haptics.answerRevealed()
            showsBloom = true
            after(schedule.bloomToTitle) { [self] in
                withAnimation(PaeoniaMotion.celebrationReveal) {
                    showsTitle = true
                    showsButtons = true
                }
                stage = .settled
            }
        }
    }

    private func applySettledState() {
        stage = .settled
        openParts = Set(Part.allCases)
        isZoomedOut = true
        showsTitle = true
        showsButtons = true
        awaitedPart = nil
    }

    /// Runs `step` after `delay` seconds, unless the run was stopped meanwhile.
    private func after(_ delay: TimeInterval, _ step: @escaping @MainActor () -> Void) {
        let id = runID
        let sleep = self.sleep
        task = Task { [weak self] in
            try? await sleep(.seconds(delay))
            guard let self, id == self.runID, !Task.isCancelled else { return }
            step()
        }
    }

    private func cancelRun() {
        runID += 1
        task?.cancel()
        task = nil
        awaitedPart = nil
    }
}
