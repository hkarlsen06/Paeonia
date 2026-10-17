import Foundation
import Testing
@testable import PaeoniaApp

struct DaysTogetherCountUpTests {
    @Test func zeroDaysHasNothingToCount() {
        let countUp = DaysTogetherCountUp(days: 0)

        #expect(countUp.duration == 0)
        #expect(countUp.value(at: 0) == 0)
        #expect(countUp.ticks.isEmpty)
    }

    @Test func countStartsAtZeroAndLandsOnTheDays() {
        let countUp = DaysTogetherCountUp(days: 812)

        #expect(countUp.value(at: 0) == 0)
        #expect(countUp.value(at: countUp.duration) == 812)
        #expect(countUp.value(at: countUp.duration + 1) == 812)
    }

    @Test func countNeverGoesBackwards() {
        let countUp = DaysTogetherCountUp(days: 365)
        let values = stride(from: 0.0, through: countUp.duration, by: 0.05).map(countUp.value(at:))

        #expect(values == values.sorted())
    }

    @Test func longRelationshipsAreCappedInTime() {
        #expect(DaysTogetherCountUp(days: 100_000).duration == DaysTogetherCountUp.maxDuration)
        #expect(DaysTogetherCountUp(days: 10).duration < DaysTogetherCountUp(days: 1_000).duration)
    }

    @Test func shortCountTicksOncePerDayBeforeTheLanding() {
        let countUp = DaysTogetherCountUp(days: 5)
        let ticks = countUp.ticks

        #expect(ticks.count == 4)
        #expect(ticks.map { $0.time } == ticks.map { $0.time }.sorted())
        #expect(ticks.map { $0.intensity } == ticks.map { $0.intensity }.sorted())
        #expect(ticks.allSatisfy { $0.time > 0 && $0.time < countUp.duration })
    }

    @Test func longCountTicksAtMostTheCap() {
        #expect(DaysTogetherCountUp(days: 5_000).ticks.count == DaysTogetherCountUp.maxTicks - 1)
    }

    @Test func ticksSpreadOutAsTheNumberSlows() {
        let times = DaysTogetherCountUp(days: 2_000).ticks.map { $0.time }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }

        #expect(gaps == gaps.sorted())
    }
}
