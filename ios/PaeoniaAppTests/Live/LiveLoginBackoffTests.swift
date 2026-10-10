import Testing
@testable import PaeoniaApp

struct LiveLoginBackoffTests {
    @Test func delayDoublesFromOneSecondAndCapsAtThirty() {
        var backoff = LiveLoginBackoff()
        let delays = (0..<8).map { _ in backoff.nextDelay() }

        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) })
    }

    @Test func resetStartsOverAtOneSecond() {
        var backoff = LiveLoginBackoff()
        _ = backoff.nextDelay()
        _ = backoff.nextDelay()
        backoff.reset()

        #expect(backoff.nextDelay() == .seconds(1))
    }
}
