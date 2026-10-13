import Foundation
import SwiftUI

/// Runs the reveal after a round ends and owns every value the view draws from
/// it. The view calls `begin` once. The steps then play on a schedule, or the
/// settled state shows at once (Reduce Motion, or a tap).
///
/// Every run has an id and each step checks it after sleeping, so no step or
/// haptic can happen after the timeline settled or stopped. The schedule, the
/// haptics, the clock and the sleep are injected, so tests run it fast.
@MainActor
@Observable
final class DrawAndGuessRevealTimeline {
    typealias Kind = DrawAndGuessRevealKind
    typealias Plan = DrawAndGuessRevealPlan
    typealias Schedule = DrawAndGuessRevealSchedule
    typealias Haptics = DrawAndGuessRevealHaptics
    typealias Event = DrawAndGuessRevealEvent
    typealias Step = DrawAndGuessRevealStep

    // MARK: State the view draws

    /// The rest of the drawing fades in over the replay.
    private(set) var finalDrawingShown = false
    /// How many letters of the answer have lit up, left to right.
    private(set) var litLetters = 0
    /// The letter that is scaling up right now.
    private(set) var rippleIndex: Int?
    private(set) var bloomStart: Date?
    private(set) var glow: Double = 0
    private(set) var gridCollapsed = false
    private(set) var canvasShrunk = false
    private(set) var titleShown = false
    private(set) var buttonShown = false
    private(set) var panelShown = false
    private(set) var scoreCounting = false
    private(set) var speedBonusShown = false
    private(set) var firstTryBonusShown = false
    /// The rows under the result appear, such as the reaction row.
    private(set) var actionsShown = false
    private(set) var isSettled = false
    /// The settled state was shown without playing, so counts should not animate.
    private(set) var wasSkipped = false

    static let restingGlow = 0.16
    static let peakGlow = 0.30
    nonisolated static let maxLetterTicks = DrawAndGuessRevealScript.maxLetterTicks

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

    /// True while a tap can still end the reveal early.
    var canSkip: Bool { hasBegun && !isSettled }

    // MARK: Entry points

    /// Starts the reveal. Later calls do nothing.
    func begin(_ plan: Plan, reduceMotion: Bool) {
        guard self.plan == nil else { return }
        self.plan = plan
        if reduceMotion {
            applySettledState(plan)
            switch plan.kind {
            case .solved: haptics.answerRevealed()
            case .missed: haptics.soft()
            }
            return
        }
        runID += 1
        let id = runID
        let steps = Self.steps(for: plan, schedule: schedule)
        task = Task { [weak self] in
            await self?.run(steps, id: id)
        }
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
        guard canSkip, let plan else { return }
        cancelRun()
        applySettledState(plan)
    }

    /// Clears the reveal and stops its run, so the same round can be played
    /// again. The round goes back to guessing when the server refused the
    /// correct guess three times, and the tiles and buttons have to come back.
    func reset() {
        cancelRun()
        plan = nil
        finalDrawingShown = false
        litLetters = 0
        rippleIndex = nil
        bloomStart = nil
        glow = 0
        gridCollapsed = false
        canvasShrunk = false
        titleShown = false
        buttonShown = false
        panelShown = false
        scoreCounting = false
        speedBonusShown = false
        firstTryBonusShown = false
        actionsShown = false
        isSettled = false
        wasSkipped = false
    }

    // MARK: Script

    /// The beats of a reveal in order. Pure, so tests read the script itself.
    nonisolated static func steps(for plan: Plan, schedule: Schedule) -> [Step] {
        DrawAndGuessRevealScript.steps(for: plan, schedule: schedule)
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
        case .start, .lightLetter, .bloom, .glowSettle, .fillStart, .fillLetter:
            applyAnswer(event)
        case .collapse, .title, .panel, .scoreTick, .speedBonus, .firstTryBonus, .actions:
            applyResult(event)
        }
    }

    /// The beats on the answer itself: the drawing, the letters, the bloom and the glow.
    private func applyAnswer(_ event: Event) {
        switch event {
        case .start:
            haptics.selection()
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)) {
                finalDrawingShown = true
                glow = Self.restingGlow
            }
        case let .lightLetter(index, tick):
            withAnimation(.spring(duration: 0.22, bounce: 0.4)) {
                litLetters = index + 1
                rippleIndex = index
            }
            if let tick { haptics.letterTick(tick) }
        case .bloom:
            rippleIndex = nil
            bloomStart = now()
            haptics.answerRevealed()
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow)) {
                glow = Self.peakGlow
            }
        case .glowSettle:
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                glow = Self.restingGlow
            }
        case .fillStart:
            finalDrawingShown = true
            haptics.soft()
        case let .fillLetter(index):
            withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)) {
                litLetters = index + 1
            }
        default:
            break
        }
    }

    /// The beats after the answer: the layout, the title, the points and the rows under them.
    private func applyResult(_ event: Event) {
        switch event {
        case .collapse:
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                gridCollapsed = true
                canvasShrunk = true
            }
        case .title:
            withAnimation(PaeoniaMotion.celebrationReveal) {
                titleShown = true
                buttonShown = true
            }
        case .panel:
            withAnimation(PaeoniaMotion.celebrationReveal) {
                panelShown = true
                scoreCounting = true
            }
        case let .scoreTick(intensity):
            haptics.scoreTick(intensity)
        case .speedBonus:
            haptics.speedBonus()
            withAnimation(PaeoniaMotion.celebrationReveal) {
                speedBonusShown = true
            }
        case .firstTryBonus:
            haptics.speedBonus()
            withAnimation(PaeoniaMotion.celebrationReveal) {
                firstTryBonusShown = true
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
        finalDrawingShown = true
        litLetters = plan.letterCount
        rippleIndex = nil
        bloomStart = nil
        glow = plan.kind == .solved ? Self.restingGlow : 0
        gridCollapsed = true
        canvasShrunk = true
        titleShown = true
        buttonShown = true
        panelShown = plan.kind == .solved && plan.pointsAdded > 0
        scoreCounting = panelShown
        speedBonusShown = plan.hasSpeedBonus
        firstTryBonusShown = plan.hasFirstTryBonus
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
