import Foundation
import Testing
@testable import PaeoniaApp

/// A recording of every haptic the reveal fires.
@MainActor
private final class HapticLog {
    var events: [String] = []
    var ticks: [CGFloat] = []

    var haptics: MindMeldRevealTimeline.Haptics {
        MindMeldRevealTimeline.Haptics(
            tick: { [self] intensity in events.append("tick"); ticks.append(intensity) },
            celebrated: { [self] in events.append("celebrated") },
            continued: { [self] in events.append("continued") },
            soft: { [self] in events.append("soft") }
        )
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

private typealias RevealTimeline = MindMeldRevealTimeline
private typealias Outcome = MindMeldRevealOutcome

private func plan(_ outcome: Outcome) -> RevealTimeline.Plan {
    RevealTimeline.Plan(outcome: outcome)
}

@MainActor
private func settle(_ timeline: RevealTimeline) async {
    _ = await waitUntil { timeline.isSettled }
}

/// The five pulse and flip ticks that come before every verdict.
private let buildUp = Array(repeating: "tick", count: 5)

/// The script and the run of a reveal.
@MainActor
struct MindMeldRevealTests {
    // MARK: Script

    @Test func theMeldScriptFollowsTheDesignedBeats() {
        let steps = RevealTimeline.steps(for: plan(.meld), schedule: .standard)

        #expect(steps.first == RevealTimeline.Step(at: 0, event: .start))
        #expect(steps.contains(RevealTimeline.Step(at: 0.20, event: .pulse(intensity: 0.3))))
        #expect(steps.contains(RevealTimeline.Step(at: 0.50, event: .pulse(intensity: 0.5))))
        #expect(steps.contains(RevealTimeline.Step(at: 0.80, event: .pulse(intensity: 0.7))))
        #expect(steps.contains(RevealTimeline.Step(at: 1.10, event: .flipMine)))
        #expect(steps.contains(RevealTimeline.Step(at: 1.55, event: .flipPartner)))
        #expect(steps.contains(RevealTimeline.Step(at: 2.10, event: .verdict(.meld))))
        #expect(steps.contains(RevealTimeline.Step(at: 2.60, event: .title)))
        #expect(steps.contains(RevealTimeline.Step(at: 2.90, event: .stats)))
        #expect(steps.last == RevealTimeline.Step(at: 3.00, event: .actions))
        #expect(steps.map(\.at) == steps.map(\.at).sorted())

        // The bloom ends 0.9 seconds after the verdict.
        let bloomEnd = steps.first { $0.event == .bloomEnd }
        #expect(abs((bloomEnd?.at ?? 0) - 3.0) < 0.001)
    }

    @Test func onlyAMeldHasTheStatsLineAndTheBloomEnd() {
        for outcome in [Outcome.near, .miss, .gotAway] {
            let steps = RevealTimeline.steps(for: plan(outcome), schedule: .standard)

            #expect(!steps.contains { $0.event == .stats }, "\(outcome)")
            #expect(!steps.contains { $0.event == .bloomEnd }, "\(outcome)")
            #expect(steps.contains(RevealTimeline.Step(at: 2.10, event: .verdict(outcome))), "\(outcome)")
            #expect(steps.last == RevealTimeline.Step(at: 3.00, event: .actions), "\(outcome)")
        }
    }

    @Test func theBloomLengthIsThePetalBloomsDuration() {
        #expect(MindMeldRevealSchedule.standard.bloomDuration == DrawAndGuessPetalBloom.duration)
    }

    @Test func theScriptFromANearMissKeepsTheGapsAfterTheVerdict() {
        let steps = MindMeldRevealScript.meldFromNearSteps(schedule: .standard)

        #expect(steps.map(\.event).prefix(3) == [.merge, .title, .stats])
        // The bloom ends and the buttons appear together, in either order.
        #expect(steps.map(\.event).suffix(2).contains(.bloomEnd))
        #expect(steps.map(\.event).suffix(2).contains(.actions))
        let times = steps.map(\.at)
        #expect(zip(times, [0, 0.5, 0.8, 0.9, 0.9]).allSatisfy { abs($0 - $1) < 0.001 })
    }

    // MARK: Run

    @Test func aMeldEndsSettledWithEveryHapticOnceAndInOrder() async {
        let log = HapticLog()
        let timeline = RevealTimeline(schedule: .instant, haptics: log.haptics, sleep: { _ in })
        timeline.begin(plan(.meld), reduceMotion: false)
        await settle(timeline)

        #expect(timeline.isSettled)
        #expect(log.events == buildUp + ["celebrated", "continued"])
        #expect(log.ticks == [0.3, 0.5, 0.7, 0.85, 0.85])
        #expect(timeline.pulse == 3)
        #expect(timeline.myCardFlipped && timeline.partnerCardFlipped && timeline.verdictShown)
        #expect(timeline.merged && !timeline.leaning && !timeline.linkDrawn)
        #expect(timeline.titleShown && timeline.statsShown && timeline.actionsShown)
        #expect(timeline.glow == RevealTimeline.restingGlow)
    }

    @Test func aNearMissLeansAndShowsNoStats() async {
        let log = HapticLog()
        let timeline = RevealTimeline(schedule: .instant, haptics: log.haptics, sleep: { _ in })
        timeline.begin(plan(.near), reduceMotion: false)
        await settle(timeline)

        #expect(log.events == buildUp + ["continued"])
        #expect(timeline.leaning && !timeline.merged && !timeline.linkDrawn)
        #expect(timeline.titleShown && !timeline.statsShown && timeline.actionsShown)
        #expect(timeline.bloomStart == nil)
    }

    @Test func aMissAndAGotAwayDrawTheLinkWithASoftHaptic() async {
        for outcome in [Outcome.miss, .gotAway] {
            let log = HapticLog()
            let timeline = RevealTimeline(schedule: .instant, haptics: log.haptics, sleep: { _ in })
            timeline.begin(plan(outcome), reduceMotion: false)
            await settle(timeline)

            #expect(log.events == buildUp + ["soft"], "\(outcome)")
            #expect(timeline.linkDrawn && !timeline.merged && !timeline.leaning, "\(outcome)")
            #expect(timeline.titleShown && !timeline.statsShown && timeline.actionsShown, "\(outcome)")
        }
    }

    @Test func theGlowRisesAtTheStartBeforeAnyPulse() async {
        let log = HapticLog()
        let gate = AsyncGate()
        let timeline = RevealTimeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.meld), reduceMotion: false)
        _ = await waitUntil { timeline.glow == RevealTimeline.restingGlow }

        #expect(timeline.pulse == 0 && log.events.isEmpty)
        #expect(!timeline.myCardFlipped && !timeline.verdictShown)
        await gate.open()
    }

    @Test func theBloomStartsAtTheVerdictAndClearsWhenItEnds() async {
        let log = HapticLog()
        let gate = AsyncGate()
        let verdictTime = Date(timeIntervalSince1970: 1_800_000_000)
        var schedule = MindMeldRevealSchedule.instant
        schedule.bloomDuration = 0.9
        let timeline = RevealTimeline(
            schedule: schedule,
            haptics: log.haptics,
            now: { verdictTime },
            sleep: { _ in await gate.wait() }
        )
        timeline.begin(plan(.meld), reduceMotion: false)
        _ = await waitUntil { timeline.actionsShown }

        #expect(timeline.bloomStart == verdictTime)
        #expect(timeline.glow == RevealTimeline.peakGlow)
        #expect(!timeline.isSettled)

        await gate.open()
        await settle(timeline)

        #expect(timeline.bloomStart == nil)
        #expect(timeline.glow == RevealTimeline.restingGlow)
    }

    // MARK: Reduce Motion, skip, stop, reset

    @Test func reduceMotionSettlesAtOnceWithOnlyTheVerdictHaptic() {
        let expected: [(Outcome, String)] = [
            (.meld, "celebrated"), (.near, "continued"), (.miss, "soft"), (.gotAway, "soft")
        ]
        for (outcome, haptic) in expected {
            let log = HapticLog()
            let timeline = RevealTimeline(haptics: log.haptics)
            timeline.begin(plan(outcome), reduceMotion: true)

            #expect(timeline.isSettled, "\(outcome)")
            #expect(timeline.bloomStart == nil && timeline.pulse == 0, "\(outcome)")
            #expect(timeline.glow == RevealTimeline.restingGlow, "\(outcome)")
            #expect(timeline.titleShown && timeline.actionsShown && timeline.verdictShown, "\(outcome)")
            #expect(timeline.merged == (outcome == .meld) && timeline.statsShown == (outcome == .meld), "\(outcome)")
            #expect(log.events == [haptic], "\(outcome)")
        }
    }

    @Test func aTapBeforeTheTitleDoesNothing() async {
        let log = HapticLog()
        let gate = AsyncGate()
        var schedule = MindMeldRevealSchedule.instant
        schedule.title = 1
        schedule.actions = 1
        let timeline = RevealTimeline(schedule: schedule, haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.miss), reduceMotion: false)
        _ = await waitUntil { timeline.verdictShown }

        #expect(!timeline.canSkip)
        timeline.skip()
        #expect(!timeline.isSettled && !timeline.titleShown)

        await gate.open()
        await settle(timeline)
        #expect(timeline.isSettled && timeline.titleShown)
    }

    @Test func aTapAfterTheTitleJumpsToTheSettledStateWithoutMoreHaptics() async {
        let log = HapticLog()
        let gate = AsyncGate()
        var schedule = MindMeldRevealSchedule.instant
        schedule.actions = 1
        let timeline = RevealTimeline(schedule: schedule, haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.meld), reduceMotion: false)
        _ = await waitUntil { timeline.titleShown }

        #expect(timeline.canSkip && !timeline.actionsShown)
        let hapticsAtSkip = log.events
        timeline.skip()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.isSettled && timeline.actionsShown && timeline.statsShown)
        #expect(timeline.bloomStart == nil)
        #expect(!timeline.canSkip)
        #expect(log.events == hapticsAtSkip)
    }

    @Test func stoppingSettlesTheStateAtAnyTimeWithoutMoreHaptics() async {
        let log = HapticLog()
        let gate = AsyncGate()
        let timeline = RevealTimeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.near), reduceMotion: false)
        _ = await waitUntil { timeline.glow == RevealTimeline.restingGlow }

        timeline.stop()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.isSettled && timeline.leaning && timeline.actionsShown)
        #expect(log.events.isEmpty)
    }

    @Test func aSecondBeginDoesNothing() {
        let timeline = RevealTimeline(haptics: HapticLog().haptics)
        timeline.begin(plan(.meld), reduceMotion: true)
        timeline.begin(plan(.miss), reduceMotion: true)

        #expect(timeline.merged && !timeline.linkDrawn)
    }

    @Test func aResetStopsTheRunAndClearsTheState() async {
        let log = HapticLog()
        let gate = AsyncGate()
        let timeline = RevealTimeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.meld), reduceMotion: false)
        _ = await waitUntil { timeline.glow == RevealTimeline.restingGlow }

        timeline.reset()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!timeline.hasBegun && !timeline.isSettled)
        #expect(timeline.glow == 0 && timeline.pulse == 0)
        #expect(!timeline.myCardFlipped && !timeline.verdictShown && !timeline.merged)
        #expect(!timeline.titleShown && !timeline.actionsShown)
        #expect(log.events.isEmpty)

        timeline.begin(plan(.miss), reduceMotion: true)
        #expect(timeline.linkDrawn && timeline.isSettled)
    }
}

/// Opening settled, and the merge after a counted near miss.
@MainActor
struct MindMeldRevealMergeTests {
    @Test func showSettledOpensInTheSettledStateWithNoHaptics() {
        for outcome in [Outcome.meld, .near, .miss, .gotAway] {
            let log = HapticLog()
            let timeline = RevealTimeline(haptics: log.haptics)
            timeline.showSettled(plan(outcome))

            #expect(timeline.isSettled && timeline.titleShown && timeline.actionsShown, "\(outcome)")
            #expect(timeline.merged == (outcome == .meld), "\(outcome)")
            #expect(timeline.leaning == (outcome == .near), "\(outcome)")
            #expect(timeline.linkDrawn == (outcome == .miss || outcome == .gotAway), "\(outcome)")
            #expect(log.events.isEmpty, "\(outcome)")

            timeline.begin(plan(.miss), reduceMotion: false)
            #expect(timeline.merged == (outcome == .meld), "\(outcome)")
        }
    }

    @Test func countingANearMissPlaysTheMergeAfterTheSettledNearState() async {
        let log = HapticLog()
        let timeline = RevealTimeline(schedule: .instant, haptics: log.haptics, sleep: { _ in })
        timeline.begin(plan(.near), reduceMotion: false)
        await settle(timeline)
        #expect(timeline.leaning && !timeline.merged)

        timeline.meldFromNear()
        #expect(!timeline.isSettled)
        await settle(timeline)

        #expect(timeline.merged && !timeline.leaning && !timeline.linkDrawn)
        #expect(timeline.titleShown && timeline.statsShown && timeline.actionsShown)
        #expect(log.events == buildUp + ["continued", "celebrated", "continued"])
    }

    @Test func theMergeBurstsTheBloomAndSwapsTheTitleBeforeTheStatsAndButtons() async {
        let log = HapticLog()
        let gate = AsyncGate()
        let mergeTime = Date(timeIntervalSince1970: 1_800_000_000)
        var schedule = MindMeldRevealSchedule.instant
        schedule.bloomDuration = 0.9
        schedule.title = 1
        schedule.stats = 1.5
        schedule.actions = 2
        let timeline = RevealTimeline(
            schedule: schedule,
            haptics: log.haptics,
            now: { mergeTime },
            sleep: { _ in await gate.wait() }
        )
        timeline.begin(plan(.near), reduceMotion: true)

        timeline.meldFromNear()
        _ = await waitUntil { timeline.bloomStart != nil }

        // The near title and buttons are gone, and the new ones are not up yet.
        #expect(timeline.merged && !timeline.leaning)
        #expect(!timeline.titleShown && !timeline.actionsShown && !timeline.statsShown)
        #expect(!timeline.canSkip)
        #expect(timeline.glow == RevealTimeline.peakGlow)
        #expect(log.events == ["continued", "celebrated"])

        await gate.open()
        await settle(timeline)

        #expect(timeline.titleShown && timeline.statsShown && timeline.actionsShown)
        #expect(timeline.bloomStart == nil)
        #expect(timeline.glow == RevealTimeline.restingGlow)
        #expect(log.events == ["continued", "celebrated", "continued"])
    }

    @Test func aTapDuringTheMergeSettlesOnTheMeld() async {
        let log = HapticLog()
        let gate = AsyncGate()
        var schedule = MindMeldRevealSchedule.instant
        schedule.actions = 1
        let timeline = RevealTimeline(schedule: schedule, haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.near), reduceMotion: true)
        timeline.meldFromNear()
        _ = await waitUntil { timeline.statsShown }

        timeline.skip()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.isSettled && timeline.merged && !timeline.leaning)
        #expect(timeline.statsShown && timeline.actionsShown)
    }

    @Test func countingBeforeTheNearRevealSettledStillEndsOnTheMeld() async {
        let log = HapticLog()
        let gate = AsyncGate()
        var schedule = MindMeldRevealSchedule.instant
        schedule.title = 1
        schedule.actions = 1
        let timeline = RevealTimeline(schedule: schedule, haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(plan(.near), reduceMotion: false)
        _ = await waitUntil { timeline.verdictShown }

        timeline.meldFromNear()
        await gate.open()
        await settle(timeline)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.merged && !timeline.leaning && timeline.statsShown && timeline.actionsShown)
        // The near haptic came once, then the merge. The old run added nothing.
        #expect(log.events == buildUp + ["continued", "celebrated", "continued"])
    }

    @Test func meldFromNearDoesNothingForOtherOutcomesOrBeforeTheReveal() {
        let log = HapticLog()
        let meld = RevealTimeline(haptics: log.haptics)
        meld.begin(plan(.meld), reduceMotion: true)
        meld.meldFromNear()
        #expect(log.events == ["celebrated"])

        let miss = RevealTimeline(haptics: log.haptics)
        miss.begin(plan(.miss), reduceMotion: true)
        miss.meldFromNear()
        #expect(miss.linkDrawn && !miss.merged)

        let fresh = RevealTimeline(haptics: log.haptics)
        fresh.meldFromNear()
        #expect(!fresh.hasBegun && !fresh.merged)
    }
}
