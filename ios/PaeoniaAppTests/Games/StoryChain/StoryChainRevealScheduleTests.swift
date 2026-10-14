import Foundation
import Testing
@testable import PaeoniaApp

/// The beats of the finished-story reveal and the timing of the title write-in.
struct StoryChainRevealScheduleTests {
    @Test func theStandardScheduleFollowsTheDesignedTimes() {
        let schedule = StoryChainRevealSchedule.standard

        #expect(schedule.scrollTop == 0.0)
        #expect(schedule.title == 0.40)
        #expect(schedule.byline == 1.10)
        #expect(schedule.ornament == 1.30)
        #expect(schedule.stats == 1.80)
        #expect(schedule.actions == 2.10)
    }

    @Test func theStandardScriptPlaysEachBeatOnceInOrder() {
        let steps = StoryChainRevealScript.steps(schedule: .standard)

        #expect(steps.map(\.event) == [.scrollTop, .title, .byline, .ornament, .stats, .actions])
        #expect(steps.map(\.at) == [0.0, 0.40, 1.10, 1.30, 1.80, 2.10])
        #expect(steps.map(\.at) == steps.map(\.at).sorted())
    }

    @Test func theInstantScheduleHasEveryBeatAtZeroAndKeepsTheOrder() {
        let schedule = StoryChainRevealSchedule.instant
        let steps = StoryChainRevealScript.steps(schedule: schedule)

        #expect(schedule.titleDuration == 0)
        #expect(steps.allSatisfy { $0.at == 0 })
        #expect(steps.map(\.event) == [.scrollTop, .title, .byline, .ornament, .stats, .actions])
    }

    @Test func aCustomScheduleIsSortedByTime() {
        var schedule = StoryChainRevealSchedule.standard
        schedule.actions = 0.5
        schedule.stats = 0.2

        let events = StoryChainRevealScript.steps(schedule: schedule).map(\.event)

        #expect(events == [.scrollTop, .stats, .title, .actions, .byline, .ornament])
    }

    @Test func theTitleFinishesWritingAboutWhenTheBylineAppears() {
        let schedule = StoryChainRevealSchedule.standard

        #expect(schedule.titleDuration == StoryChainTitleTiming.totalDuration)
        #expect(abs((schedule.title + schedule.titleDuration) - schedule.byline) < 0.1)
    }

    // MARK: Title timing

    @Test func aShortTitleWritesInOneLetterEvery30Milliseconds() {
        #expect(StoryChainTitleTiming.gap(letterCount: 12) == 0.030)
        // The second letter has not started at 30 ms, the first one has.
        #expect(StoryChainTitleTiming.letterProgress(index: 0, letterCount: 12, elapsed: 0.030) > 0)
        #expect(StoryChainTitleTiming.letterProgress(index: 1, letterCount: 12, elapsed: 0.030) == 0)
        #expect(StoryChainTitleTiming.letterProgress(index: 1, letterCount: 12, elapsed: 0.060) > 0)
    }

    @Test func aLongTitleCompressesSoTheLastLetterStartsWithinTheSpan() {
        let count = 40
        let gap = StoryChainTitleTiming.gap(letterCount: count)

        #expect(gap < 0.030)
        #expect(gap * Double(count - 1) <= StoryChainTitleTiming.maxSpan + 1e-6)
    }

    @Test func everyLetterIsSharpWhenTheProgressReachesOne() {
        for count in [1, 6, 17, 40] {
            let elapsed = StoryChainTitleTiming.elapsed(forProgress: 1)
            for index in 0..<count {
                let value = StoryChainTitleTiming.letterProgress(index: index, letterCount: count, elapsed: elapsed)
                #expect(value >= 0.999)
            }
            #expect(StoryChainTitleTiming.letterProgress(index: 0, letterCount: count, elapsed: 0) == 0)
        }
    }

    @Test func letterProgressNeverGoesBackwards() {
        for index in [0, 5, 11] {
            var previous = 0.0
            for step in 0...100 {
                let progress = Double(step) / 100
                let elapsed = StoryChainTitleTiming.elapsed(forProgress: progress)
                let value = StoryChainTitleTiming.letterProgress(index: index, letterCount: 12, elapsed: elapsed)
                #expect(value >= previous)
                previous = value
            }
        }
    }

    @Test func theProgressIsClampedToZeroAndOne() {
        #expect(StoryChainTitleTiming.elapsed(forProgress: -1) == 0)
        #expect(StoryChainTitleTiming.elapsed(forProgress: 2) == StoryChainTitleTiming.totalDuration)
        #expect(StoryChainTitleTiming.letterProgress(index: 0, letterCount: 0, elapsed: 0) == 1)
    }
}
