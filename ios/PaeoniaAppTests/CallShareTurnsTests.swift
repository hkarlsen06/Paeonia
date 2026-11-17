import Testing
@testable import PaeoniaApp

struct CallShareTurnsTests {
    /// Two phones in one call. Each hands its turn to the other, as the `screen` relay message does.
    private struct Call {
        var caller = CallShareTurns()
        var called = CallShareTurns()

        mutating func callerTells() {
            called.partnerChanged(to: caller.own)
        }

        mutating func calledTells() {
            caller.partnerChanged(to: called.own)
        }

        var callerGivesWay: Bool {
            caller.ownGivesWay(isCaller: true)
        }

        var calledGivesWay: Bool {
            called.ownGivesWay(isCaller: false)
        }
    }

    @Test func aShareStartedWhileThePartnerSharesTakesOver() {
        var call = Call()
        call.caller.startOwn()
        call.callerTells()

        call.called.startOwn()
        call.calledTells()
        #expect(call.callerGivesWay)
        #expect(!call.calledGivesWay)

        call.caller.stopOwn()
        call.callerTells()
        #expect(!call.calledGivesWay)

        // The caller takes it back the same way.
        call.caller.startOwn()
        call.callerTells()
        #expect(call.calledGivesWay)
        #expect(!call.callerGivesWay)
    }

    @Test func sharesStartedBeforeEitherHeardTheOtherLeaveTheCallersShare() {
        var call = Call()
        call.caller.startOwn()
        call.called.startOwn()
        call.callerTells()
        call.calledTells()
        #expect(!call.callerGivesWay)
        #expect(call.calledGivesWay)
    }

    @Test func aShareThatWasStartingWhenThePartnerStartedTakesOverOnceItRuns() {
        var call = Call()
        call.caller.startOwn()
        call.callerTells()
        // The called phone's share is still starting, so it has no turn and keeps going.
        #expect(!call.calledGivesWay)

        call.called.startOwn()
        call.calledTells()
        #expect(call.callerGivesWay)
        #expect(!call.calledGivesWay)
    }
}
