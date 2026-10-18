import Foundation
import Testing
@testable import PaeoniaApp

/// A recording of every haptic the reveal fires.
@MainActor
private final class HapticLog {
    var events: [String] = []
    var letterTicks: [CGFloat] = []

    var haptics: DrawAndGuessRevealTimeline.Haptics {
        DrawAndGuessRevealTimeline.Haptics(
            selection: { [self] in events.append("selection") },
            letterTick: { [self] tick in events.append("letter"); letterTicks.append(tick) },
            answerRevealed: { [self] in events.append("revealed") },
            soft: { [self] in events.append("soft") },
            scoreTick: { [self] _ in events.append("score") },
            speedBonus: { [self] in events.append("bonus") }
        )
    }
}

@MainActor
struct DrawAndGuessRevealTests {
    private typealias Timeline = DrawAndGuessRevealTimeline

    private func plan(
        _ kind: Timeline.Kind = .solved,
        letters: Int = 8,
        points: Int = 3,
        bonus: Bool = true,
        firstTry: Bool = false
    ) -> Timeline.Plan {
        Timeline.Plan(
            kind: kind,
            letterCount: letters,
            pointsAdded: points,
            hasSpeedBonus: bonus,
            hasFirstTryBonus: firstTry
        )
    }

    private func settle(_ timeline: Timeline) async {
        _ = await waitUntil { timeline.isSettled }
    }

    // MARK: Script

    @Test func theSolvedScriptFollowsTheDesignedBeats() {
        let steps = Timeline.steps(for: plan(letters: 8, firstTry: true), schedule: .standard)

        #expect(steps.first == Timeline.Step(at: 0, event: .start))
        // Eight letters at 45 ms start as the last tile lands at 0.16 s, and the last one lights at 0.475 s.
        let lights = steps.filter { if case .lightLetter = $0.event { true } else { false } }
        #expect(lights.count == 8)
        #expect(abs((lights.last?.at ?? 0) - 0.475) < 0.001)
        #expect(steps.contains(Timeline.Step(at: 0.70, event: .bloom)))
        #expect(steps.contains(Timeline.Step(at: 1.10, event: .title)))
        #expect(steps.contains(Timeline.Step(at: 1.40, event: .panel)))
        // The bonus lines land after the count, and the first-try line has its own beat.
        #expect(steps.contains(Timeline.Step(at: 2.30, event: .speedBonus)))
        #expect(steps.contains(Timeline.Step(at: 2.60, event: .firstTryBonus)))
        #expect(steps.last == Timeline.Step(at: 2.90, event: .actions))
        #expect(steps.map(\.at) == steps.map(\.at).sorted())
    }

    @Test func theCountWaitsForThePanelAndEachTickMovesTheTotal() {
        let steps = Timeline.steps(for: plan(points: 3), schedule: .standard)
        let ticks = steps.compactMap { step -> (at: TimeInterval, progress: Double)? in
            if case let .scoreTick(progress, _) = step.event { (step.at, progress) } else { nil }
        }

        #expect(ticks.count == 3)
        #expect(abs(ticks[0].at - 1.70) < 0.001)
        #expect(abs(ticks[2].at - 2.10) < 0.001)
        #expect(ticks.map(\.progress) == [1.0 / 3, 2.0 / 3, 1])
        // The count is over before the first bonus line lands.
        #expect(ticks[2].at < 2.30)
    }

    @Test func aSinglePointCountsOnTheFirstBeatAtFullStrength() {
        let steps = Timeline.steps(for: plan(points: 1), schedule: .standard)
        let ticks = steps.filter { if case .scoreTick = $0.event { true } else { false } }

        #expect(ticks.count == 1)
        #expect(abs((ticks.first?.at ?? 0) - 1.70) < 0.001)
        guard case let .scoreTick(progress, intensity) = ticks.first?.event else { return }
        #expect(progress == 1)
        #expect(abs(intensity - 0.85) < 0.001)
    }

    @Test func aLongPhraseStillFinishesLightingByHalfASecondAfterTheStart() {
        let steps = Timeline.steps(for: plan(letters: 20), schedule: .standard)
        let lights = steps.filter { if case .lightLetter = $0.event { true } else { false } }

        #expect(lights.count == 20)
        #expect((lights.last?.at ?? 0) <= 0.60 + 0.0001)
    }

    @Test func atMostEightLetterTicksRiseFromQuietToStrong() {
        let steps = Timeline.steps(for: plan(letters: 20), schedule: .standard)
        let ticks = steps.compactMap { step -> CGFloat? in
            if case let .lightLetter(_, tick) = step.event { tick } else { nil }
        }

        #expect(ticks.count <= Timeline.maxLetterTicks)
        #expect(ticks == ticks.sorted())
        #expect(abs((ticks.first ?? 0) - 0.25) < 0.001)
        #expect(abs((ticks.last ?? 0) - 0.85) < 0.001)
    }

    @Test func noBonusMeansNoBonusBeatAndNoPointsMeansNoPanel() {
        let steps = Timeline.steps(for: plan(points: 0, bonus: false), schedule: .standard)

        #expect(!steps.contains { $0.event == .speedBonus })
        #expect(!steps.contains { $0.event == .firstTryBonus })
        #expect(!steps.contains { $0.event == .panel })
    }

    @Test func aMissedRoundFillsQuietlyWithoutBloomOrPanel() {
        let steps = Timeline.steps(for: plan(.missed, letters: 8), schedule: .standard)

        #expect(!steps.contains { $0.event == .bloom })
        #expect(!steps.contains { $0.event == .panel })
        #expect(steps.filter { if case .fillLetter = $0.event { true } else { false } }.count == 8)
    }

    // MARK: Run

    @Test func theRunEndsSettledWithEveryHapticOnce() async {
        let log = HapticLog()
        let timeline = Timeline(schedule: .instant, haptics: log.haptics, sleep: { _ in })
        timeline.begin(plan(letters: 4, points: 3, firstTry: true), reduceMotion: false)
        await settle(timeline)

        #expect(timeline.isSettled)
        #expect(timeline.litLetters == 4)
        #expect(timeline.titleShown && timeline.buttonShown && timeline.panelShown && timeline.actionsShown)
        #expect(timeline.speedBonusShown && timeline.firstTryBonusShown)
        #expect(timeline.scoreProgress == 1)
        #expect(timeline.bloomStart != nil)
        #expect(log.events.filter { $0 == "revealed" }.count == 1)
        #expect(log.events.filter { $0 == "selection" }.count == 1)
        // One for the speed bonus and one for the first-try bonus.
        #expect(log.events.filter { $0 == "bonus" }.count == 2)
        #expect(log.events.filter { $0 == "letter" }.count == 4)
        #expect(log.events.filter { $0 == "score" }.count == 3)
        // The answer lands after the letters, and the bonus after the answer.
        let revealed = log.events.firstIndex(of: "revealed") ?? -1
        let lastLetter = log.events.lastIndex(of: "letter") ?? Int.max
        let bonus = log.events.firstIndex(of: "bonus") ?? -1
        #expect(revealed > lastLetter)
        #expect(bonus > revealed)
    }

    @Test func reduceMotionSettlesAtOnceWithOnlyTheRevealHaptic() {
        let log = HapticLog()
        let timeline = Timeline(haptics: log.haptics)
        timeline.begin(plan(), reduceMotion: true)

        #expect(timeline.isSettled)
        #expect(timeline.bloomStart == nil)
        #expect(timeline.glow == Timeline.restingGlow)
        #expect(timeline.litLetters == 8)
        #expect(timeline.wasSkipped)
        #expect(log.events == ["revealed"])
    }

    @Test func aTapJumpsToTheSettledStateWithoutMoreHaptics() async {
        let log = HapticLog()
        let gate = AsyncGate()
        // The first sleep never returns until released, so the run stops mid-script.
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(), reduceMotion: false)
        _ = await waitUntil { log.events == ["selection"] }

        timeline.skip()
        let hapticsAtSkip = log.events
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.isSettled)
        #expect(timeline.wasSkipped)
        #expect(timeline.titleShown && timeline.actionsShown)
        #expect(timeline.bloomStart == nil)
        #expect(log.events == hapticsAtSkip)
    }

    @Test func aSecondBeginDoesNothing() {
        let timeline = Timeline(haptics: HapticLog().haptics)
        timeline.begin(plan(letters: 3), reduceMotion: true)
        timeline.begin(plan(letters: 9), reduceMotion: true)

        #expect(timeline.litLetters == 3)
    }

    @Test func aResetStopsTheRunAndShowsTheTilesAgain() async {
        let log = HapticLog()
        let gate = AsyncGate()
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(), reduceMotion: false)
        _ = await waitUntil { log.events == ["selection"] }

        timeline.reset()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!timeline.hasBegun)
        #expect(!timeline.gridCollapsed && !timeline.canvasShrunk)
        #expect(!timeline.buttonShown && !timeline.titleShown && !timeline.isSettled)
        #expect(timeline.litLetters == 0 && !timeline.finalDrawingShown)
        #expect(timeline.scoreProgress == 0)
        #expect(log.events == ["selection"])
    }

    @Test func aSettledRevealCanPlayAgainAfterAReset() {
        let timeline = Timeline(haptics: HapticLog().haptics)
        timeline.begin(plan(letters: 3), reduceMotion: true)
        timeline.reset()
        #expect(!timeline.gridCollapsed && !timeline.wasSkipped)

        timeline.begin(plan(letters: 9), reduceMotion: true)
        #expect(timeline.litLetters == 9 && timeline.gridCollapsed && timeline.buttonShown)
    }
}

/// Holds a sleeping task until the test lets it go.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
