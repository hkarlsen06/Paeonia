import Foundation
import Testing
@testable import PaeoniaApp

/// A recording of every haptic the reveal fires.
@MainActor
private final class HapticLog {
    var events: [String] = []
    var foldIntensities: [CGFloat] = []

    var haptics: ExquisiteCorpseRevealTimeline.Haptics {
        ExquisiteCorpseRevealTimeline.Haptics(
            selection: { [self] in events.append("selection") },
            foldLanded: { [self] intensity in events.append("fold"); foldIntensities.append(intensity) },
            answerRevealed: { [self] in events.append("revealed") }
        )
    }
}

/// Records how long each step asked to wait, to the millisecond, and returns at once.
private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var durations: [TimeInterval] { lock.withLock { recorded } }

    func sleep(_ duration: Duration) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        lock.withLock { recorded.append((seconds * 1_000).rounded() / 1_000) }
    }
}

/// Holds a sleeping task until the test lets it go.
private actor SleepGate {
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

@MainActor
struct ExquisiteCorpseRevealTimelineTests {
    private typealias Timeline = ExquisiteCorpseRevealTimeline

    private func instantTimeline(_ log: HapticLog, sleeps: SleepLog = SleepLog()) -> Timeline {
        Timeline(haptics: log.haptics, sleep: { sleeps.sleep($0) })
    }

    /// Plays the view's part: waits for the replay to start, then reports it finished at once.
    private func play(_ part: ExquisiteCorpsePartKind, on timeline: Timeline) async {
        _ = await waitUntil { timeline.stage == .playing(part) }
        timeline.partReplayFinished(part)
    }

    private func playEverything(on timeline: Timeline) async {
        for part in ExquisiteCorpsePartKind.allCases {
            await play(part, on: timeline)
        }
        _ = await waitUntil { timeline.isSettled }
    }

    // MARK: Pure helpers

    @Test func aLongDrawingPlaysFasterToFitInTwoAndAHalfSeconds() {
        #expect(Timeline.replayRate(duration: 5) == 2)
        #expect(Timeline.replayRate(duration: 10) == 4)
        #expect(Timeline.replayRate(duration: 12.5) == 5)
    }

    @Test func aShortDrawingPlaysAtItsOwnPace() {
        #expect(Timeline.replayRate(duration: 0) == 1)
        #expect(Timeline.replayRate(duration: 1) == 1)
        #expect(Timeline.replayRate(duration: 2.5) == 1)
    }

    @Test func theFoldHapticBuildsUpFromHeadToLegs() {
        #expect(ExquisiteCorpsePartKind.allCases.map(Timeline.foldIntensity(for:)) == [0.4, 0.6, 0.85])
    }

    // MARK: Run

    @Test func theFoldedPaperSitsStillWithAHapticBeforeTheFirstFoldOpens() {
        let log = HapticLog()
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        timeline.begin(reduceMotion: false)

        #expect(timeline.hasBegun)
        #expect(timeline.stage == .folded)
        #expect(timeline.openParts.isEmpty)
        #expect(!timeline.isZoomedOut && !timeline.showsBloom && !timeline.showsTitle && !timeline.showsButtons)
        #expect(log.events == ["selection"])
        timeline.stop()
    }

    @Test func eachFoldOpensWhenThePartBeforeItFinishedReplaying() async {
        let log = HapticLog()
        let timeline = instantTimeline(log)
        timeline.begin(reduceMotion: false)

        _ = await waitUntil { timeline.stage == .playing(.head) }
        #expect(timeline.openParts == [.head])
        #expect(log.foldIntensities == [0.4])

        // Nothing moves on until the view says the head finished.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(timeline.stage == .playing(.head))
        #expect(timeline.openParts == [.head])

        timeline.partReplayFinished(.head)
        _ = await waitUntil { timeline.stage == .playing(.body) }
        #expect(timeline.openParts == [.head, .body])
        #expect(log.foldIntensities == [0.4, 0.6])

        timeline.partReplayFinished(.body)
        _ = await waitUntil { timeline.stage == .playing(.legs) }
        #expect(timeline.openParts == [.head, .body, .legs])
        #expect(log.foldIntensities == [0.4, 0.6, 0.85])
        #expect(!timeline.isZoomedOut && !timeline.showsTitle)
    }

    @Test func theRunEndsSettledWithEveryHapticOnceInOrder() async {
        let log = HapticLog()
        let timeline = instantTimeline(log)
        timeline.begin(reduceMotion: false)
        // A part with no strokes finishes the moment it starts, and the run goes on.
        await playEverything(on: timeline)

        #expect(timeline.stage == .settled)
        #expect(timeline.openParts == [.head, .body, .legs])
        #expect(timeline.isZoomedOut)
        #expect(timeline.showsBloom)
        #expect(timeline.showsTitle && timeline.showsButtons)
        #expect(log.events == ["selection", "fold", "fold", "fold", "revealed"])
        #expect(log.foldIntensities == [0.4, 0.6, 0.85])
    }

    @Test func theBeatsWaitAsLongAsTheDesignSays() async {
        let sleeps = SleepLog()
        let timeline = instantTimeline(HapticLog(), sleeps: sleeps)
        timeline.begin(reduceMotion: false)
        await playEverything(on: timeline)

        // First fold, then for each part the fold opening and the pause after its replay,
        // then the zoom out to the bloom and the bloom to the title.
        let fold = 0.36
        #expect(sleeps.durations == [0.3, fold, 0.3, fold, 0.3, fold, 0.3, 0.6])
    }

    @Test func theWholeFigureShowsBeforeTheTitleAndTheButtons() async {
        let log = HapticLog()
        let gate = SleepGate()
        // Only the last pause, from the bloom to the title, is held.
        let timeline = Timeline(haptics: log.haptics, sleep: { duration in
            if duration == .seconds(0.6) { await gate.wait() }
        })
        timeline.begin(reduceMotion: false)
        for part in ExquisiteCorpsePartKind.allCases {
            await play(part, on: timeline)
        }
        _ = await waitUntil { timeline.showsBloom }

        #expect(timeline.stage == .zoomingOut)
        #expect(timeline.isZoomedOut && timeline.showsBloom)
        #expect(!timeline.showsTitle && !timeline.showsButtons)
        #expect(log.events.last == "revealed")

        await gate.open()
        _ = await waitUntil { timeline.isSettled }
        #expect(timeline.showsTitle && timeline.showsButtons)
    }

    @Test func aReportForAPartThatIsNotPlayingIsIgnored() async {
        let sleeps = SleepLog()
        let timeline = instantTimeline(HapticLog(), sleeps: sleeps)
        timeline.begin(reduceMotion: false)
        _ = await waitUntil { timeline.stage == .playing(.head) }

        timeline.partReplayFinished(.body)
        timeline.partReplayFinished(.legs)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(timeline.stage == .playing(.head))

        // A second report of the head does not open the body twice.
        timeline.partReplayFinished(.head)
        timeline.partReplayFinished(.head)
        _ = await waitUntil { timeline.stage == .playing(.body) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(timeline.stage == .playing(.body))
        #expect(sleeps.durations == [0.3, 0.36, 0.3, 0.36])
    }

    @Test func aReportBeforeTheReplayStartsIsIgnored() {
        let timeline = Timeline(haptics: HapticLog().haptics, sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        timeline.begin(reduceMotion: false)

        timeline.partReplayFinished(.head)

        #expect(timeline.stage == .folded)
        timeline.stop()
    }

    // MARK: Reduce Motion

    @Test func reduceMotionShowsTheWholeFigureAtOnceWithOnlyTheRevealHaptic() {
        let log = HapticLog()
        let sleeps = SleepLog()
        let timeline = instantTimeline(log, sleeps: sleeps)
        timeline.begin(reduceMotion: true)

        #expect(timeline.stage == .settled)
        #expect(timeline.openParts == [.head, .body, .legs])
        #expect(timeline.isZoomedOut)
        #expect(timeline.showsTitle && timeline.showsButtons)
        #expect(!timeline.showsBloom)
        #expect(log.events == ["revealed"])
        #expect(sleeps.durations.isEmpty)
    }

    // MARK: Skip, stop and reset

    @Test func aTapJumpsToTheSettledStateWithoutMoreHaptics() async {
        let log = HapticLog()
        let gate = SleepGate()
        // The first sleep never returns until released, so the run stops at the start.
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(reduceMotion: false)
        #expect(timeline.canSkip)

        timeline.skip()
        let hapticsAtSkip = log.events
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.stage == .settled)
        #expect(timeline.openParts == [.head, .body, .legs])
        #expect(timeline.isZoomedOut && timeline.showsTitle && timeline.showsButtons)
        #expect(!timeline.showsBloom)
        #expect(!timeline.canSkip)
        #expect(log.events == hapticsAtSkip)
        #expect(log.events == ["selection"])
    }

    @Test func aTapDuringAReplayStopsTheReportsFromDoingAnything() async {
        let log = HapticLog()
        let timeline = instantTimeline(log)
        timeline.begin(reduceMotion: false)
        _ = await waitUntil { timeline.stage == .playing(.head) }

        timeline.skip()
        timeline.partReplayFinished(.head)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.stage == .settled)
        #expect(log.events == ["selection", "fold"])
    }

    @Test func aTapAfterTheBloomStartedKeepsTheBloom() async {
        let log = HapticLog()
        let gate = SleepGate()
        let timeline = Timeline(haptics: log.haptics, sleep: { duration in
            if duration == .seconds(0.6) { await gate.wait() }
        })
        timeline.begin(reduceMotion: false)
        for part in ExquisiteCorpsePartKind.allCases {
            await play(part, on: timeline)
        }
        _ = await waitUntil { timeline.showsBloom }

        timeline.skip()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.stage == .settled)
        #expect(timeline.showsBloom)
        #expect(timeline.showsTitle && timeline.showsButtons)
        // The reveal haptic did not fire a second time.
        #expect(log.events.filter { $0 == "revealed" }.count == 1)
    }

    @Test func skipDoesNothingBeforeBeginOrOnceSettled() {
        let timeline = Timeline(haptics: HapticLog().haptics)

        timeline.skip()
        #expect(timeline.stage == .folded && !timeline.hasBegun && !timeline.canSkip)

        timeline.begin(reduceMotion: true)
        timeline.skip()
        #expect(timeline.stage == .settled)
    }

    @Test func leavingTheScreenEndsTheRunAndSettlesIt() async {
        let log = HapticLog()
        let gate = SleepGate()
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(reduceMotion: false)

        timeline.stop()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(timeline.stage == .settled)
        #expect(log.events == ["selection"])
    }

    @Test func aSecondBeginDoesNothing() {
        let log = HapticLog()
        let timeline = Timeline(haptics: log.haptics)
        timeline.begin(reduceMotion: true)
        timeline.begin(reduceMotion: false)

        #expect(timeline.stage == .settled)
        #expect(log.events == ["revealed"])
    }

    @Test func aResetStopsTheRunAndLetsTheRevealPlayAgain() async {
        let log = HapticLog()
        let gate = SleepGate()
        let timeline = Timeline(haptics: log.haptics, sleep: { _ in await gate.wait() })
        timeline.begin(reduceMotion: false)

        timeline.reset()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!timeline.hasBegun)
        #expect(timeline.stage == .folded)
        #expect(timeline.openParts.isEmpty)
        #expect(!timeline.isZoomedOut && !timeline.showsBloom && !timeline.showsTitle && !timeline.showsButtons)
        #expect(log.events == ["selection"])

        // The gate is open, so the second run goes through at once.
        timeline.begin(reduceMotion: false)
        await playEverything(on: timeline)
        #expect(timeline.stage == .settled)
        #expect(log.events == ["selection", "selection", "fold", "fold", "fold", "revealed"])
    }
}
