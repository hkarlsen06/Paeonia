import Foundation
import Testing
@testable import PaeoniaApp

/// The beats of the finished-story reveal and the timing of the title write-in.
struct StoryChainRevealScheduleTests {
    @Test func theStandardScheduleFollowsTheDesignedTimes() {
        let schedule = StoryChainRevealSchedule.standard

        #expect(schedule.scrollTop == 0.0)
        #expect(schedule.title == 0.50)
        #expect(schedule.bloom == 1.20)
        #expect(schedule.byline == 1.55)
        #expect(schedule.ornament == 1.60)
        #expect(schedule.stats == 1.75)
        #expect(schedule.actions == 1.85)
    }

    @Test func theStandardScriptPlaysEachBeatOnceInOrder() {
        let steps = StoryChainRevealScript.steps(schedule: .standard)

        #expect(steps.map(\.event) == [.scrollTop, .title, .bloom, .byline, .ornament, .stats, .actions])
        #expect(steps.map(\.at) == [0.0, 0.50, 1.20, 1.55, 1.60, 1.75, 1.85])
        #expect(steps.map(\.at) == steps.map(\.at).sorted())
    }

    @Test func theInstantScheduleHasEveryBeatAtZeroAndKeepsTheOrder() {
        let schedule = StoryChainRevealSchedule.instant
        let steps = StoryChainRevealScript.steps(schedule: schedule)

        #expect(schedule.titleDuration == 0)
        #expect(steps.allSatisfy { $0.at == 0 })
        #expect(steps.map(\.event) == [.scrollTop, .title, .bloom, .byline, .ornament, .stats, .actions])
    }

    @Test func aCustomScheduleIsSortedByTime() {
        var schedule = StoryChainRevealSchedule.standard
        schedule.actions = 0.5
        schedule.stats = 0.2

        let events = StoryChainRevealScript.steps(schedule: schedule).map(\.event)

        #expect(events == [.scrollTop, .stats, .title, .actions, .bloom, .byline, .ornament])
    }

    @Test func thePetalsBurstAsTheLastLetterOfATypicalTitleLands() {
        let schedule = StoryChainRevealSchedule.standard
        let landing = schedule.bloom - schedule.title

        #expect(schedule.titleDuration == StoryChainTitleTiming.totalDuration)
        // An 18-letter title has its last letter nearly sharp at the burst, not long before.
        let last = StoryChainTitleTiming.letterProgress(index: 17, letterCount: 18, elapsed: landing)
        #expect(last > 0.9)
        #expect(StoryChainTitleTiming.letterProgress(index: 17, letterCount: 18, elapsed: landing - 0.15) < 0.9)
        // The page scroll (a 0.6 s ease-out) has nearly settled before the title starts.
        #expect(schedule.title >= 0.4)
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
