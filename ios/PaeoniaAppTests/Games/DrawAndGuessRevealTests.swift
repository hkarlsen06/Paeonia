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
        bonus: Bool = true
    ) -> Timeline.Plan {
        Timeline.Plan(kind: kind, letterCount: letters, pointsAdded: points, hasSpeedBonus: bonus)
    }

    private func settle(_ timeline: Timeline) async {
        _ = await waitUntil { timeline.isSettled }
    }

    // MARK: Script

    @Test func theSolvedScriptFollowsTheDesignedBeats() {
        let steps = Timeline.steps(for: plan(letters: 8), schedule: .standard)

        #expect(steps.first == Timeline.Step(at: 0, event: .start))
        // Eight letters at 45 ms start at 0.10 s and the last one lights at 0.415 s.
        let lights = steps.filter { if case .lightLetter = $0.event { true } else { false } }
        #expect(lights.count == 8)
        #expect(abs((lights.last?.at ?? 0) - 0.415) < 0.001)
        #expect(steps.contains(Timeline.Step(at: 0.70, event: .bloom)))
        #expect(steps.contains(Timeline.Step(at: 1.10, event: .title)))
        #expect(steps.contains(Timeline.Step(at: 1.40, event: .panel)))
        #expect(steps.contains(Timeline.Step(at: 1.90, event: .speedBonus)))
        #expect(steps.last == Timeline.Step(at: 2.20, event: .save))
        #expect(steps.map(\.at) == steps.map(\.at).sorted())
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
        timeline.begin(plan(letters: 4, points: 3), reduceMotion: false)
        await settle(timeline)

        #expect(timeline.isSettled)
        #expect(timeline.litLetters == 4)
        #expect(timeline.titleShown && timeline.buttonShown && timeline.panelShown && timeline.saveShown)
        #expect(timeline.speedBonusShown)
        #expect(timeline.bloomStart != nil)
        #expect(log.events.filter { $0 == "revealed" }.count == 1)
        #expect(log.events.filter { $0 == "selection" }.count == 1)
        #expect(log.events.filter { $0 == "bonus" }.count == 1)
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
        #expect(timeline.titleShown && timeline.saveShown)
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

    // MARK: Score

    private func reveal(
        outcome: DrawAndGuessReveal.Outcome = .iSolvedIt,
        bonus: Int? = 1,
        isConfirmed: Bool = true,
        duration: TimeInterval? = 18
    ) -> DrawAndGuessReveal {
        let solved = outcome == .iSolvedIt || outcome == .partnerSolvedIt
        return DrawAndGuessReveal(
            outcome: outcome,
            word: "umbrella",
            difficulty: .medium,
            wordPoints: 2,
            speedBonus: bonus,
            solveDuration: duration,
            pointsForMe: solved ? 2 + (outcome == .iSolvedIt ? bonus ?? 0 : 0) : 0,
            pointsForCouple: solved ? 2 : 0,
            attempts: [],
            isConfirmed: isConfirmed
        )
    }

    @Test func theGuesserGetsTheWordAndTheBonusAndTheDrawerGetsTheWord() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: true
        ))

        guard case let .against(mine, partner) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(mine.before == 5 && mine.after == 8)
        #expect(mine.lines.map(\.kind) == [.word, .speedBonus])
        #expect(partner.before == 3 && partner.after == 5)
        #expect(partner.lines.map(\.kind) == [.drawing])
        #expect(!score.isEstimate)
        #expect(score.largestGain == 3)
    }

    @Test func theDrawerSeesTheBonusInThePartnersColumn() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(outcome: .partnerSolvedIt),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: false
        ))

        guard case let .against(mine, partner) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(mine.added == 2 && mine.lines.map(\.kind) == [.drawing])
        #expect(partner.added == 3 && partner.lines.map(\.kind) == [.word, .speedBonus])
    }

    @Test func togetherCountsTheCouplesTotalByTheWordOnly() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(),
            score: .together(total: 13),
            iAmGuesser: true
        ))

        guard case let .together(column) = score.style else {
            Issue.record("Expected the together style")
            return
        }
        #expect(column.before == 11 && column.after == 13)
    }

    @Test func aResultOnlyOnThePhoneAddsToTheTotalsAndHasNoBonus() throws {
        let score = try #require(DrawAndGuessRevealScore.make(
            reveal: reveal(bonus: nil, isConfirmed: false),
            score: .against(mine: 8, partner: 5),
            iAmGuesser: true
        ))

        guard case let .against(mine, _) = score.style else {
            Issue.record("Expected the against style")
            return
        }
        #expect(score.isEstimate)
        #expect(mine.before == 8 && mine.after == 10)
        #expect(mine.lines.map(\.kind) == [.word])
    }

    @Test func aMissedRoundHasNoScorePanel() {
        let missed = reveal(outcome: .iGaveUp, bonus: 0)

        #expect(DrawAndGuessRevealScore.make(reveal: missed, score: .together(total: 3), iAmGuesser: true) == nil)
    }

    @Test func aSolveTimePastTenMinutesIsNotShown() {
        #expect(reveal(duration: 24).shownSolveDuration == 24)
        #expect(reveal(duration: 600).shownSolveDuration == 600)
        #expect(reveal(duration: 601).shownSolveDuration == nil)
        #expect(reveal(duration: nil).shownSolveDuration == nil)
    }

    // MARK: Chips

    @Test func theChipsComeHalfASecondApartButTakeThreeSecondsAtMost() {
        #expect(DrawAndGuessChipPlayback.interval(chipCount: 2) == 0.5)
        #expect(DrawAndGuessChipPlayback.interval(chipCount: 6) == 0.5)
        #expect(DrawAndGuessChipPlayback.interval(chipCount: 12) == 0.25)
        #expect(DrawAndGuessChipPlayback.interval(chipCount: 0) == 0)
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
