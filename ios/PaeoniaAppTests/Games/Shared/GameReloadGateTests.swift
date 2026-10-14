import Testing
@testable import PaeoniaApp

/// Which reload's read reaches the screen when reloads overlap. `#expect` can't
/// call the mutating `apply`, so each result is kept first.
struct GameReloadGateTests {
    @Test func readsThatFinishInOrderAllApply() {
        var gate = GameReloadGate()

        let first = gate.begin()
        let firstApplied = gate.apply(first)
        let second = gate.begin()
        let secondApplied = gate.apply(second)

        #expect(firstApplied)
        #expect(secondApplied)
    }

    @Test func aLaterReloadStillReadingDoesNotDropAnEarlierRead() {
        var gate = GameReloadGate()
        let earlier = gate.begin()
        let later = gate.begin()

        let earlierApplied = gate.apply(earlier)
        let laterApplied = gate.apply(later)

        #expect(earlierApplied)
        #expect(laterApplied)
    }

    @Test func aLaterReloadAlreadyAppliedDropsAnEarlierRead() {
        var gate = GameReloadGate()
        let earlier = gate.begin()
        let later = gate.begin()

        let laterApplied = gate.apply(later)
        let earlierApplied = gate.apply(earlier)

        #expect(laterApplied)
        #expect(!earlierApplied)
    }

    @Test func aReadIsAppliedOnlyOnce() {
        var gate = GameReloadGate()
        let ticket = gate.begin()

        let firstTime = gate.apply(ticket)
        let secondTime = gate.apply(ticket)

        #expect(firstTime)
        #expect(!secondTime)
    }
}
