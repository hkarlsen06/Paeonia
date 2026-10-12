import Testing
@testable import PaeoniaApp

struct DrawAndGuessReplayClockTests {
    @Test func runsAtTheDrawnPaceFromTheStart() {
        let clock = DrawAndGuessReplayClock(duration: 10, startingAt: 100)

        #expect(clock.replayTime(at: 100) == 0)
        #expect(clock.replayTime(at: 103.5) == 3.5)
    }

    @Test func neverRunsPastTheEndOrBeforeTheStart() {
        let clock = DrawAndGuessReplayClock(duration: 10, startingAt: 100)

        #expect(clock.replayTime(at: 500) == 10)
        #expect(clock.isFinished(at: 500))
        #expect(!clock.isFinished(at: 109))
        #expect(clock.replayTime(at: 90) == 0)
    }

    @Test func changingTheRateDoesNotJump() {
        var clock = DrawAndGuessReplayClock(duration: 100, startingAt: 0)

        clock.setRate(DrawAndGuessReplayClock.fastForwardRate, at: 2)
        #expect(clock.replayTime(at: 2) == 2)
        #expect(clock.replayTime(at: 3) == 6)

        clock.setRate(1, at: 3)
        #expect(clock.replayTime(at: 3) == 6)
        #expect(clock.replayTime(at: 5) == 8)
    }

    @Test func releasingAtTheEndStaysAtTheEnd() {
        var clock = DrawAndGuessReplayClock(duration: 5, startingAt: 0)

        clock.setRate(4, at: 1)
        clock.setRate(1, at: 10)

        #expect(clock.replayTime(at: 10) == 5)
        #expect(clock.replayTime(at: 20) == 5)
    }

    @Test func rateZeroPauses() {
        var clock = DrawAndGuessReplayClock(duration: 10, startingAt: 0)

        clock.setRate(0, at: 3)

        #expect(clock.replayTime(at: 50) == 3)
        clock.setRate(1, at: 50)
        #expect(clock.replayTime(at: 52) == 5)
    }

    @Test func finishJumpsToTheEndForTheReveal() {
        var clock = DrawAndGuessReplayClock(duration: 10, startingAt: 0)

        clock.finish(at: 2)

        #expect(clock.replayTime(at: 2) == 10)
        #expect(clock.isFinished(at: 2))
    }

    @Test func emptyDrawingIsFinishedAtOnce() {
        let clock = DrawAndGuessReplayClock(duration: 0, startingAt: 0)

        #expect(clock.isFinished(at: 0))
    }
}
