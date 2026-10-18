import Foundation
import SwiftUI

/// The haptics and sounds of the reveal, injected so tests can record them.
struct MindMeldRevealHaptics {
    /// The build-up pulses and the card flips.
    var tick: @MainActor (CGFloat) -> Void
    /// A meld lands.
    var celebrated: @MainActor () -> Void
    /// A near miss lands, and the meld stats appear.
    var continued: @MainActor () -> Void
    /// A miss lands.
    var soft: @MainActor () -> Void

    static let live = Self(
        tick: { intensity in
            PaeoniaHaptics.streakTick(intensity: intensity)
            // The pulses stay below the flips' strength, so the strength tells them apart.
            if intensity >= MindMeldRevealScript.flipIntensity {
                GameSound.flip.play()
            } else {
                GameSound.tick.play(volume: intensity + 0.3)
            }
        },
        celebrated: {
            PaeoniaHaptics.streakCelebrated()
            GameSound.win.play()
        },
        continued: {
            PaeoniaHaptics.streakContinued()
            GameSound.tap.play(volume: 0.7)
        },
        soft: {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.soft.play()
        }
    )
}

/// Runs the reveal of a round and owns every value the view draws from it. The
/// view calls `begin` once. The beats then play on a schedule, or the settled
/// state shows at once (Reduce Motion, a tap, or `showSettled`).
///
/// Every run has an id and each step checks it after sleeping, so no step or
/// haptic can happen after the timeline settled or stopped. The schedule, the
/// haptics, the clock and the sleep are injected, so tests run it fast.
@MainActor
@Observable
final class MindMeldRevealTimeline {
    typealias Plan = MindMeldRevealPlan
    typealias Schedule = MindMeldRevealSchedule
    typealias Haptics = MindMeldRevealHaptics
    typealias Event = MindMeldRevealEvent
    typealias Step = MindMeldRevealStep

    // MARK: State the view draws

    /// The glow behind the cards.
    private(set) var glow: Double = 0
    /// Goes up by one at each build-up pulse. The view pulses the cards on each change.
    private(set) var pulse = 0
    private(set) var myCardFlipped = false
    private(set) var partnerCardFlipped = false
    /// The outcome is on the table. The three flags below say how the cards show it.
    private(set) var verdictShown = false
    /// The cards slide together into one.
    private(set) var merged = false
    /// The sliding cards have touched. The partner's card hides under mine and the borders turn green.
    private(set) var joined = false
    /// The cards lean toward each other.
    private(set) var leaning = false
    /// A line is drawn between the cards.
    private(set) var linkDrawn = false
    /// When the petal bloom started. Nil before it and after `bloomDuration`.
    private(set) var bloomStart: Date?
    private(set) var titleShown = false
    private(set) var statsShown = false
    /// The buttons appear.
    private(set) var actionsShown = false
    private(set) var isSettled = false

    @ObservationIgnored private let schedule: Schedule
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var plan: Plan?
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

    var hasBegun: Bool { plan != nil }

    /// A tap can end the reveal early once the title is up.
    var canSkip: Bool { hasBegun && titleShown && !isSettled }

    // MARK: Entry points

    /// Starts the reveal. Later calls do nothing.
    func begin(_ plan: Plan, reduceMotion: Bool) {
        guard self.plan == nil else { return }
        self.plan = plan
        if reduceMotion {
            applySettledState(plan)
            playVerdictHaptic(plan.outcome)
            return
        }
        start(Self.steps(for: plan, schedule: schedule))
    }

    /// Opens straight in the settled state with no haptics, for a game whose
    /// ending the person has already seen. Later calls do nothing.
    func showSettled(_ plan: Plan) {
        guard self.plan == nil else { return }
        self.plan = plan
        applySettledState(plan)
    }

    /// Jumps to the settled state without repeating haptics.
    func skip() {
        guard canSkip, let plan else { return }
        cancelRun()
        withAnimation(PaeoniaMotion.stateChange) {
            applySettledState(plan)
        }
    }

    /// Ends the run when the view goes away.
    func stop() {
        guard hasBegun, !isSettled, let plan else { return }
        cancelRun()
        applySettledState(plan)
    }

    /// Clears the reveal and stops its run, so the next round can play.
    func reset() {
        cancelRun()
        plan = nil
        glow = 0
        pulse = 0
        myCardFlipped = false
        partnerCardFlipped = false
        verdictShown = false
        merged = false
        joined = false
        leaning = false
        linkDrawn = false
        bloomStart = nil
        titleShown = false
        statsShown = false
        actionsShown = false
        isSettled = false
    }

    /// A partner counted the near miss on screen. The cards slide together, the
    /// bloom bursts, and the title and buttons change to the meld's. Does
    /// nothing unless the reveal is for a near miss.
    func meldFromNear() {
        guard let current = plan, current.outcome == .near else { return }
        cancelRun()
        if !isSettled {
            applySettledState(current)
        }
        plan = Plan(outcome: .meld)
        isSettled = false
        start(MindMeldRevealScript.meldFromNearSteps(schedule: schedule))
    }

    // MARK: Script

    /// The beats of a reveal in order. Pure, so tests read the script itself.
    nonisolated static func steps(for plan: Plan, schedule: Schedule) -> [Step] {
        MindMeldRevealScript.steps(for: plan, schedule: schedule)
    }

    private func start(_ steps: [Step]) {
        runID += 1
        let id = runID
        task = Task { [weak self] in
            await self?.run(steps, id: id)
        }
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
        case .start, .pulse, .flipMine, .flipPartner:
            applyBuildUp(event)
        case .verdict, .contact, .bloomEnd, .merge:
            applyVerdict(event)
        case .title, .stats, .actions:
            applyResult(event)
        }
    }

    /// The beats before the verdict: the glow, the pulses and the flips.
    private func applyBuildUp(_ event: Event) {
        switch event {
        case .start:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow)) {
                glow = Self.restingGlow
            }
        case let .pulse(intensity):
            pulse += 1
            haptics.tick(intensity)
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)) {
                glow = Self.restingGlow + Self.pulseGlowStep * Double(pulse)
            }
        case .flipMine:
            haptics.tick(MindMeldRevealScript.flipIntensity)
            withAnimation(PaeoniaMotion.standardCurve(duration: Self.flipDuration)) {
                myCardFlipped = true
            }
        case .flipPartner:
            haptics.tick(MindMeldRevealScript.flipIntensity)
            withAnimation(PaeoniaMotion.standardCurve(duration: Self.flipDuration)) {
                partnerCardFlipped = true
            }
        default:
            break
        }
    }

    /// The verdict, the bloom that follows a meld, and the merge of a counted near miss.
    private func applyVerdict(_ event: Event) {
        switch event {
        case let .verdict(outcome):
            land(outcome)
            // A meld's haptic waits for the cards to touch.
            if outcome != .meld {
                playVerdictHaptic(outcome)
            }
        case .merge:
            // The near title and buttons leave quickly, so they never cross the meld's.
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)) {
                titleShown = false
                actionsShown = false
            }
            withAnimation(Self.slide) {
                leaning = false
                merged = true
            }
        case .contact:
            joined = true
            bloomStart = now()
            haptics.celebrated()
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow)) {
                glow = Self.peakGlow
            }
        case .bloomEnd:
            bloomStart = nil
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                glow = Self.restingGlow
            }
        default:
            break
        }
    }

    /// The beats after the verdict: the title, the stats line and the buttons.
    private func applyResult(_ event: Event) {
        switch event {
        case .title:
            withAnimation(PaeoniaMotion.celebrationReveal) {
                titleShown = true
            }
        case .stats:
            haptics.continued()
            withAnimation(PaeoniaMotion.celebrationReveal) {
                statsShown = true
            }
        case .actions:
            withAnimation(PaeoniaMotion.cardReveal) {
                actionsShown = true
            }
        default:
            break
        }
    }

    private func applySettledState(_ plan: Plan) {
        glow = Self.restingGlow
        myCardFlipped = true
        partnerCardFlipped = true
        verdictShown = true
        merged = plan.outcome == .meld
        joined = merged
        leaning = plan.outcome == .near
        linkDrawn = plan.outcome == .miss || plan.outcome == .gotAway
        bloomStart = nil
        titleShown = true
        statsShown = plan.outcome == .meld
        actionsShown = true
        isSettled = true
    }

    private func cancelRun() {
        runID += 1
        task?.cancel()
        task = nil
    }
}

// MARK: - Outcomes

private extension MindMeldRevealTimeline {
    /// Shows the outcome on the cards. The haptic is the caller's.
    func land(_ outcome: MindMeldRevealOutcome) {
        verdictShown = true
        switch outcome {
        case .meld:
            withAnimation(Self.slide) {
                merged = true
            }
        case .near:
            withAnimation(PaeoniaMotion.cardReveal) {
                leaning = true
            }
        case .miss, .gotAway:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                linkDrawn = true
            }
        }
        // The glow the pulses built up falls back, and a meld's rises again when the cards touch.
        if outcome != .meld {
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                glow = Self.restingGlow
            }
        }
    }

    func playVerdictHaptic(_ outcome: MindMeldRevealOutcome) {
        switch outcome {
        case .meld: haptics.celebrated()
        case .near: haptics.continued()
        case .miss, .gotAway: haptics.soft()
        }
    }
}

// MARK: - Tuning

extension MindMeldRevealTimeline {
    static let restingGlow = 0.16
    static let peakGlow = 0.40
    static let flipDuration: TimeInterval = 0.4
    /// How much the glow rises at each build-up pulse.
    static let pulseGlowStep = 0.05
    /// How long the cards of a meld slide before they touch.
    static let slideDuration: TimeInterval = 0.24
    /// The cards speed up into each other, like two magnets, so they hit instead of settling.
    static let slide = Animation.timingCurve(0.55, 0, 0.9, 0.45, duration: slideDuration)
}
