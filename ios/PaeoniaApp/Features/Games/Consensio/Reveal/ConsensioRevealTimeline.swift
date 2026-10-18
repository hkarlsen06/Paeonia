import Foundation
import SwiftUI

/// The haptics and sounds of the reveal, injected so tests can record them.
struct ConsensioRevealHaptics {
    /// A build-up pulse or a point counting up.
    var tick: @MainActor (CGFloat) -> Void
    /// The other marker plants in the line.
    var landed: @MainActor () -> Void
    var spotOn: @MainActor () -> Void
    var close: @MainActor () -> Void
    var far: @MainActor () -> Void

    static let live = Self(
        tick: { intensity in
            PaeoniaHaptics.streakTick(intensity: intensity)
            GameSound.tick.play(volume: intensity + 0.1)
        },
        landed: {
            PaeoniaHaptics.answerRevealed()
            GameSound.chime.play()
        },
        spotOn: {
            PaeoniaHaptics.streakCelebrated()
            GameSound.win.play()
        },
        close: {
            PaeoniaHaptics.streakContinued()
            GameSound.bonus.play()
        },
        far: {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.soft.play()
        }
    )
}

/// Runs the reveal of a round and owns every value the view draws from it. The
/// view calls `begin` once. The beats then play on a schedule, or the settled
/// state shows at once (Reduce Motion or a tap).
///
/// Every run has an id and each step checks it after sleeping, so no step or
/// haptic can happen after the timeline settled or stopped.
@MainActor
@Observable
final class ConsensioRevealTimeline {
    typealias Plan = ConsensioRevealPlan
    typealias Schedule = ConsensioRevealSchedule

    // MARK: State the view draws

    /// The line dims while the build-up runs.
    private(set) var dimmed = false
    /// Goes up by one at each build-up pulse. The view pulses the standing marker.
    private(set) var pulse = 0
    /// The other marker is on the line.
    private(set) var dropped = false
    /// How much of the gold thread is drawn, 0 to 1.
    private(set) var thread: Double = 0
    private(set) var verdict: ConsensioVerdict?
    /// When the petal bloom started. Nil before it and after it.
    private(set) var bloomStart: Date?
    private(set) var titleShown = false
    /// How many of the round's points have counted up.
    private(set) var countedPoints = 0
    private(set) var actionsShown = false
    private(set) var isSettled = false

    @ObservationIgnored private let schedule: Schedule
    @ObservationIgnored private let haptics: ConsensioRevealHaptics
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var plan: Plan?
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        schedule: Schedule = .standard,
        haptics: ConsensioRevealHaptics? = nil,
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

    /// The first frame of a held reveal: the known marker alone on a dim line.
    func hold() {
        guard plan == nil else { return }
        dimmed = true
    }

    /// Starts the reveal. Later calls do nothing.
    func begin(_ plan: Plan, reduceMotion: Bool) {
        guard self.plan == nil else { return }
        self.plan = plan
        if reduceMotion {
            applySettledState(plan)
            playVerdictHaptic(plan.verdict)
            return
        }
        start(ConsensioRevealScript.steps(for: plan, schedule: schedule))
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

    // MARK: Script

    private func start(_ steps: [ConsensioRevealStep]) {
        runID += 1
        let id = runID
        task = Task { [weak self] in
            await self?.run(steps, id: id)
        }
    }

    private func run(_ steps: [ConsensioRevealStep], id: Int) async {
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

    private func apply(_ event: ConsensioRevealEvent) {
        switch event {
        case .start, .pulse, .drop, .thread:
            applyBuildUp(event)
        case .verdict, .bloomEnd, .title, .point, .actions:
            applyResult(event)
        }
    }

    /// The beats before the verdict: the dim line, the pulses, the drop and the thread.
    private func applyBuildUp(_ event: ConsensioRevealEvent) {
        switch event {
        case .start:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow)) {
                dimmed = true
            }
        case let .pulse(intensity):
            pulse += 1
            haptics.tick(intensity)
        case .drop:
            haptics.landed()
            withAnimation(.spring(duration: PaeoniaMotion.motionSlow, bounce: 0.3)) {
                dropped = true
            }
        case .thread:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                thread = 1
            }
        default:
            break
        }
    }

    /// The verdict and what follows it: the bloom, the title, the points and the button.
    private func applyResult(_ event: ConsensioRevealEvent) {
        switch event {
        case let .verdict(verdict):
            playVerdictHaptic(verdict)
            if verdict == .spotOn {
                bloomStart = now()
            }
            withAnimation(PaeoniaMotion.cardReveal) {
                self.verdict = verdict
                dimmed = false
            }
        case .bloomEnd:
            bloomStart = nil
        case .title:
            withAnimation(PaeoniaMotion.celebrationReveal) {
                titleShown = true
            }
        case let .point(count):
            haptics.tick(ConsensioRevealScript.pointIntensity)
            withAnimation(PaeoniaMotion.buttonPress) {
                countedPoints = count
            }
        case .actions:
            withAnimation(PaeoniaMotion.cardReveal) {
                actionsShown = true
            }
        default:
            break
        }
    }

    private func playVerdictHaptic(_ verdict: ConsensioVerdict) {
        switch verdict {
        case .spotOn: haptics.spotOn()
        case .soClose, .close: haptics.close()
        case .far: haptics.far()
        }
    }

    private func applySettledState(_ plan: Plan) {
        dimmed = false
        dropped = true
        thread = 1
        verdict = plan.verdict
        bloomStart = nil
        titleShown = true
        countedPoints = plan.points
        actionsShown = true
        isSettled = true
    }

    private func cancelRun() {
        runID += 1
        task?.cancel()
        task = nil
    }
}
