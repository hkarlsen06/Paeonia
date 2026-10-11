import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the celebration script: the completion callback fires exactly once,
/// a skip settles the screen at once, and no step or haptic runs after a skip.
/// Step durations are short and injected. Waits that expect "nothing happens"
/// last several times longer than the whole intro.
@MainActor
struct PairingCelebrationTimelineTests {
    private static let fastSchedule = PairingCelebrationSchedule(
        heartAppear: 0.04,
        absorb: 0.3,
        partnerHold: 0.05,
        landingSettle: 0.05,
        partnerPhotoGrace: 0.02,
        partnerNameWait: 0.2,
        pulses: [
            PairingCelebrationSchedule.Pulse(intensity: 0.3, gap: 0.02),
            PairingCelebrationSchedule.Pulse(intensity: 0.9, gap: 0.02)
        ]
    )

    private let log = StepLog()

    private func makeTimeline() -> PairingCelebrationTimeline {
        PairingCelebrationTimeline(schedule: Self.fastSchedule, haptics: log.haptics)
    }

    private func begin(
        _ timeline: PairingCelebrationTimeline,
        playsIntro: Bool = true,
        reduceMotion: Bool = false,
        partnerNameKnown: Bool = true
    ) {
        let log = log
        timeline.begin(
            playsIntro: playsIntro,
            reduceMotion: reduceMotion,
            partnerNameKnown: partnerNameKnown,
            onIntroComplete: { log.completions += 1 }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func letAnyLateStepRun() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    // MARK: - Full intro

    @Test func introRunsEveryStepOnceAndCompletesOnce() async {
        let timeline = makeTimeline()
        begin(timeline)

        #expect(timeline.mode == .playing)
        #expect(log.completions == 1)

        let settled = await waitUntil { timeline.isSettled }
        #expect(settled)
        #expect(log.events == ["buildUp", "buildUp", "burst", "linked"])
        #expect(timeline.dismissButtonShown)
        #expect(!timeline.canSkip)
        #expect(log.completions == 1)
    }

    // MARK: - Skipping

    @Test func skippingMidIntroSettlesAtOnceAndNothingRunsAfterwards() async {
        let timeline = makeTimeline()
        begin(timeline)
        let reachedAbsorb = await waitUntil { log.events.contains("buildUp") }
        #expect(reachedAbsorb)

        timeline.skip()
        let eventsAtSkip = log.events

        #expect(timeline.mode == .settled)
        #expect(timeline.isSettled)
        #expect(timeline.dismissButtonShown)
        #expect(!timeline.showsParticles)
        #expect(log.completions == 1)

        await letAnyLateStepRun()

        #expect(log.events == eventsAtSkip)
        #expect(!log.events.contains("burst"))
        #expect(!log.events.contains("linked"))
        #expect(timeline.mode == .settled)
        #expect(timeline.phase == .settled)
        #expect(!timeline.partnerRevealed)
        #expect(log.completions == 1)
    }

    @Test func skippingBeforeTheFirstStepRunsNoStepAtAll() async {
        let timeline = makeTimeline()
        begin(timeline)
        timeline.skip()

        await letAnyLateStepRun()

        #expect(log.events.isEmpty)
        #expect(timeline.heartOpacity == 0)
        #expect(timeline.mode == .settled)
        #expect(log.completions == 1)
    }

    @Test func skippingTwiceOrAfterTheIntroEndedDoesNothingMore() async {
        let timeline = makeTimeline()
        begin(timeline)
        timeline.skip()
        timeline.skip()
        timeline.stop()
        #expect(log.completions == 1)

        let other = makeTimeline()
        begin(other)
        let settled = await waitUntil { other.isSettled }
        #expect(settled)
        let eventsAtSettle = log.events
        other.skip()
        #expect(log.events == eventsAtSettle)
        #expect(log.completions == 2)
    }

    @Test func stoppingARunningIntroEndsItWithoutLateSteps() async {
        let timeline = makeTimeline()
        begin(timeline)
        timeline.stop()

        await letAnyLateStepRun()

        #expect(log.events.isEmpty)
        #expect(timeline.mode == .settled)
        #expect(log.completions == 1)
    }

    // MARK: - Waiting for the partner

    @Test func waitsForThePartnerNameThenPlaysWhenItArrives() async {
        let timeline = makeTimeline()
        begin(timeline, partnerNameKnown: false)

        #expect(timeline.mode == .waitingForPartner)
        #expect(timeline.showsHeart)
        #expect(!timeline.showsParticles)
        #expect(timeline.canSkip)
        #expect(log.completions == 0)

        timeline.partnerNameDidArrive()
        #expect(timeline.mode == .playing)
        #expect(log.completions == 1)

        let settled = await waitUntil { timeline.isSettled }
        #expect(settled)
        #expect(log.completions == 1)
    }

    @Test func startsAnywayWhenThePartnerNameNeverArrives() async {
        let timeline = makeTimeline()
        begin(timeline, partnerNameKnown: false)

        let started = await waitUntil { timeline.mode == .playing }
        #expect(started)
        #expect(log.completions == 1)

        let settled = await waitUntil { timeline.isSettled }
        #expect(settled)
        #expect(log.completions == 1)
    }

    @Test func skippingWhileWaitingSettlesAndNeverStartsTheIntro() async {
        let timeline = makeTimeline()
        begin(timeline, partnerNameKnown: false)
        timeline.skip()

        #expect(timeline.mode == .settled)
        #expect(log.completions == 1)

        await letAnyLateStepRun()
        timeline.partnerNameDidArrive()

        #expect(timeline.mode == .settled)
        #expect(log.events.isEmpty)
        #expect(log.completions == 1)
    }

    // MARK: - No intro

    @Test func reduceMotionSettlesAtOnceWithoutWaiting() {
        let timeline = makeTimeline()
        begin(timeline, reduceMotion: true, partnerNameKnown: false)

        #expect(timeline.mode == .settled)
        #expect(timeline.dismissButtonShown)
        #expect(log.events == ["settledWithoutIntro"])
        #expect(log.completions == 1)
    }

    @Test func launchWithoutAnIntroSettlesQuietly() {
        let timeline = makeTimeline()
        begin(timeline, playsIntro: false)

        #expect(timeline.mode == .settled)
        #expect(timeline.dismissButtonShown)
        #expect(log.events.isEmpty)
        #expect(log.completions == 1)
    }

    @Test func beginningTwiceIsIgnored() {
        let timeline = makeTimeline()
        begin(timeline, playsIntro: false)
        begin(timeline, playsIntro: false)

        #expect(log.completions == 1)
    }
}

/// Records the haptics the timeline fires and how often it reports completion.
@MainActor
private final class StepLog {
    private(set) var events: [String] = []
    var completions = 0

    var haptics: PairingCelebrationHaptics {
        PairingCelebrationHaptics(
            buildUp: { [self] _ in events.append("buildUp") },
            burst: { [self] in events.append("burst") },
            linked: { [self] in events.append("linked") },
            settledWithoutIntro: { [self] in events.append("settledWithoutIntro") }
        )
    }
}
