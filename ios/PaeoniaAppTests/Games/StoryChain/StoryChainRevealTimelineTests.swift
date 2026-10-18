import Foundation
import Testing
@testable import PaeoniaApp

/// A recording of every haptic the reveal fires.
@MainActor
private final class RevealHapticLog {
    var events: [String] = []

    var haptics: StoryChainRevealTimeline.Haptics {
        StoryChainRevealTimeline.Haptics(
            selection: { [self] in events.append("selection") },
            answerRevealed: { [self] in events.append("revealed") }
        )
    }
}

/// Holds the timeline's sleeps. The first `passes` sleeps return at once, and
/// later ones wait until `open`.
private actor RevealGate {
    private let passes: Int
    private var calls = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(passing passes: Int = 0) {
        self.passes = passes
    }

    func wait() async {
        calls += 1
        if isOpen || calls <= passes { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting {
            continuation.resume()
        }
        waiting = []
    }
}

@MainActor
struct StoryChainRevealTimelineTests {
    private typealias Timeline = StoryChainRevealTimeline

    private let story = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1") ?? UUID()
    private let burst = Date(timeIntervalSince1970: 1_700_000_000)

    private func settle(_ timeline: Timeline) async {
        _ = await waitUntil { timeline.isSettled }
    }

    private func expectNothingShown(_ timeline: Timeline) {
        #expect(!timeline.scrolledToTop)
        #expect(!timeline.titleShown && timeline.titleProgress == 0)
        #expect(!timeline.bylineShown && !timeline.ornamentShown)
        #expect(!timeline.statsShown && !timeline.actionsShown)
        #expect(timeline.bloomStart == nil)
        #expect(!timeline.isSettled && !timeline.wasSkipped)
    }

    private func expectEverythingShown(_ timeline: Timeline) {
        #expect(timeline.scrolledToTop)
        #expect(timeline.titleShown && timeline.titleProgress == 1)
        #expect(timeline.bylineShown && timeline.ornamentShown)
        #expect(timeline.statsShown && timeline.actionsShown)
        #expect(timeline.isSettled)
    }

    // MARK: Run

    @Test func aTimelineThatHasNotBegunShowsNothing() {
        let timeline = Timeline(haptics: RevealHapticLog().haptics)

        expectNothingShown(timeline)
        #expect(!timeline.hasBegun && !timeline.canSkip)
        #expect(timeline.storyID == nil)
    }

    @Test func theInstantRunShowsEverythingWithBothHapticsOnceInOrder() async {
        let log = RevealHapticLog()
        let moment = burst
        let timeline = Timeline(schedule: .instant, haptics: log.haptics, now: { moment }, sleep: { _ in })
        timeline.begin(storyID: story, reduceMotion: false)
        await settle(timeline)

        expectEverythingShown(timeline)
        #expect(timeline.storyID == story)
        #expect(timeline.bloomStart == burst)
        #expect(!timeline.wasSkipped)
        // The title writes in with a tick, and its petals burst with the success haptic.
        #expect(log.events == ["selection", "revealed"])
    }

    @Test func theBeatsPlayInTheDesignedOrder() async {
        let log = RevealHapticLog()
        let gate = RevealGate(passing: 1)
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(storyID: story, reduceMotion: false)

        // The page scrolls up at once. The title is the first beat after a sleep.
        _ = await waitUntil { timeline.titleShown }
        #expect(timeline.scrolledToTop)
        #expect(timeline.titleProgress == 1)
        #expect(!timeline.bylineShown && !timeline.ornamentShown && !timeline.actionsShown)
        #expect(timeline.bloomStart == nil)
        #expect(log.events == ["selection"])

        await gate.open()
        await settle(timeline)
        expectEverythingShown(timeline)
        #expect(log.events == ["selection", "revealed"])
    }

    @Test func aSecondBeginDoesNothing() {
        let log = RevealHapticLog()
        let timeline = Timeline(haptics: log.haptics)
        timeline.begin(storyID: story, reduceMotion: true)
        timeline.begin(storyID: UUID(), reduceMotion: true)

        #expect(timeline.storyID == story)
        #expect(log.events == ["revealed"])
    }

    // MARK: Reduce Motion

    @Test func reduceMotionSettlesAtOnceWithOnlyTheSuccessHaptic() {
        let log = RevealHapticLog()
        let timeline = Timeline(haptics: log.haptics)
        timeline.begin(storyID: story, reduceMotion: true)

        expectEverythingShown(timeline)
        #expect(timeline.wasSkipped)
        #expect(timeline.bloomStart == nil)
        #expect(!timeline.canSkip)
        #expect(log.events == ["revealed"])
    }

    // MARK: Skip

    @Test func aTapJumpsToTheSettledStateWithoutMoreHaptics() async {
        let log = RevealHapticLog()
        let gate = RevealGate()
        // The first sleep never returns until released, so the run stops after the first beat.
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(storyID: story, reduceMotion: false)
        _ = await waitUntil { timeline.scrolledToTop }
        #expect(timeline.canSkip)

        timeline.skip()
        let hapticsAtSkip = log.events
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        expectEverythingShown(timeline)
        #expect(timeline.wasSkipped)
        #expect(timeline.bloomStart == nil)
        #expect(!timeline.canSkip)
        #expect(hapticsAtSkip.isEmpty)
        #expect(log.events == hapticsAtSkip)
    }

    @Test func aTapAfterTheTitleKeepsTheTitleHapticAndFiresNothingElse() async {
        let log = RevealHapticLog()
        let gate = RevealGate(passing: 1)
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(storyID: story, reduceMotion: false)
        _ = await waitUntil { timeline.titleShown }

        timeline.skip()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        expectEverythingShown(timeline)
        #expect(log.events == ["selection"])
    }

    @Test func skipDoesNothingBeforeTheRunBeginsAndAfterItSettled() async {
        let timeline = Timeline(schedule: .instant, haptics: RevealHapticLog().haptics, sleep: { _ in })
        timeline.skip()
        expectNothingShown(timeline)

        timeline.begin(storyID: story, reduceMotion: false)
        await settle(timeline)
        timeline.skip()

        #expect(!timeline.wasSkipped)
    }

    @Test func stopSettlesWithoutHaptics() async {
        let log = RevealHapticLog()
        let gate = RevealGate()
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(storyID: story, reduceMotion: false)
        _ = await waitUntil { timeline.scrolledToTop }

        timeline.stop()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        expectEverythingShown(timeline)
        #expect(log.events.isEmpty)
    }

    // MARK: Reset

    @Test func aResetStopsTheRunAndClearsEverything() async {
        let log = RevealHapticLog()
        let gate = RevealGate(passing: 1)
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(storyID: story, reduceMotion: false)
        _ = await waitUntil { log.events == ["selection"] }

        timeline.reset()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        expectNothingShown(timeline)
        #expect(!timeline.hasBegun)
        #expect(log.events == ["selection"])
    }

    @Test func aSettledRevealCanPlayAgainAfterAReset() {
        let log = RevealHapticLog()
        let timeline = Timeline(haptics: log.haptics)
        timeline.begin(storyID: story, reduceMotion: true)
        timeline.reset()
        expectNothingShown(timeline)

        let other = UUID()
        timeline.begin(storyID: other, reduceMotion: true)

        expectEverythingShown(timeline)
        #expect(timeline.storyID == other)
        #expect(log.events == ["revealed", "revealed"])
    }
}
