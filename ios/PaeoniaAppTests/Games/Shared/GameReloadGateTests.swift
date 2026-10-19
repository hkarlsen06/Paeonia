import Testing
@testable import PaeoniaApp

/// Which reload's read reaches the screen when reloads overlap. `#expect` can't
/// call the mutating `apply`, so each result is kept first.
struct GameReloadGateTests {
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
