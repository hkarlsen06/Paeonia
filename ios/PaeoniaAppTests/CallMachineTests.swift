import Foundation
import Testing
@testable import PaeoniaApp

struct CallMachineTests {
    private let callID = UUID()
    private let deviceID = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func outgoing() -> CallMachine {
        CallMachine.outgoing(callID: callID, deviceID: deviceID, ringDeadline: start + 50).0
    }

    private func incoming() -> CallMachine {
        CallMachine.incoming(callID: callID, deviceID: deviceID, ringDeadline: start + 50).0
    }

    private func row(_ state: LiveCall.State, id: UUID? = nil, answeredOn device: UUID? = nil) -> LiveCall {
        LiveCall(
            callID: id ?? callID,
            callerUserID: UUID(),
            calleeUserID: UUID(),
            state: state,
            answeredDeviceID: device,
            ringExpiresAt: start + 45
        )
    }

    @Test func outgoingCallConnectsAfterThePartnerAnswers() {
        var machine = outgoing()
        _ = machine.reduce(.registered(callID: callID, answeredIncoming: false), now: start)
        _ = machine.reduce(.liveCall(row(.ringing)), now: start + 1)
        #expect(machine.phase == .ringing)

        let answered = machine.reduce(.liveCall(row(.active, answeredOn: UUID())), now: start + 5)
        #expect(machine.phase == .connecting)
        #expect(answered.contains(.cancelTimer(.ring)))
        #expect(answered.contains(.connectMedia))

        let connected = machine.reduce(.connected, now: start + 7)
        #expect(machine.phase == .active(since: start + 7))
        #expect(connected.contains(.startTimer(.audioActivation, fireAt: start + 12)))
    }

    @Test func reconnectingKeepsTheCallTimeAndGivesUpAfterTheTimer() {
        var machine = outgoing()
        _ = machine.reduce(.registered(callID: callID, answeredIncoming: false), now: start)
        _ = machine.reduce(.liveCall(row(.active)), now: start + 5)
        _ = machine.reduce(.connected, now: start + 7)

        let lost = machine.reduce(.connectionLost, now: start + 60)
        #expect(machine.phase == .reconnecting(since: start + 7))
        #expect(lost.contains(.restartConnection))
        #expect(lost.contains(.startTimer(.reconnect, fireAt: start + 90)))

        _ = machine.reduce(.connected, now: start + 70)
        #expect(machine.phase == .active(since: start + 7))

        _ = machine.reduce(.connectionLost, now: start + 80)
        let effects = machine.reduce(.timerFired(.reconnect), now: start + 110)
        #expect(machine.phase == .ended(.failed(.couldNotConnect)))
        #expect(effects == [.finish(.failed(.couldNotConnect), server: .end)])
    }

    @Test func aMissingRowEndsTheCallOnlyAfterTheRowWasSeen() {
        var machine = outgoing()
        _ = machine.reduce(.registered(callID: callID, answeredIncoming: false), now: start)
        // The live query can still hold the result from before `start_call`.
        #expect(machine.reduce(.liveCall(nil), now: start + 1).isEmpty)
        #expect(machine.phase == .ringing)

        _ = machine.reduce(.liveCall(row(.ringing)), now: start + 2)
        let effects = machine.reduce(.liveCall(nil), now: start + 30)
        #expect(machine.phase == .ended(.noAnswer))
        #expect(effects == [.finish(.noAnswer, server: nil)])
    }

    @Test func theRowGoingAwayDuringACallIsAHangUp() {
        var machine = incoming()
        _ = machine.reduce(.answered, now: start + 3)
        _ = machine.reduce(.connected, now: start + 4)
        _ = machine.reduce(.liveCall(nil), now: start + 100)
        #expect(machine.phase == .ended(.hungUp))
    }

    @Test func anIncomingCallAnsweredOnAnotherDeviceStopsRingingHere() {
        var machine = incoming()
        #expect(machine.reduce(.liveCall(row(.active, answeredOn: deviceID)), now: start + 2).isEmpty)
        #expect(machine.phase == .ringing)

        let effects = machine.reduce(.liveCall(row(.active, answeredOn: UUID())), now: start + 2)
        #expect(machine.phase == .ended(.answeredElsewhere))
        #expect(effects == [.finish(.answeredElsewhere, server: nil)])
    }

    @Test func hangingUpDeclinesARingAndEndsAnAnsweredCall() {
        var ringing = incoming()
        #expect(ringing.reduce(.hangUp, now: start) == [.finish(.hungUp, server: .decline)])

        var answered = incoming()
        _ = answered.reduce(.answered, now: start)
        #expect(answered.reduce(.hangUp, now: start + 1) == [.finish(.hungUp, server: .end)])

        // The server never heard of a call that `start_call` has not returned for.
        var unregistered = outgoing()
        #expect(unregistered.reduce(.hangUp, now: start) == [.finish(.hungUp, server: nil)])
    }

    @Test func aStartWithoutAnAnswerStillEndsTheCallOnTheServer() {
        // A refusal means the server has no call, but a lost answer may hide one that rings.
        var refused = outgoing()
        #expect(refused.reduce(.failed(.other), now: start) == [.finish(.failed(.other), server: nil)])

        var unconfirmed = outgoing()
        let effects = unconfirmed.reduce(.startUnconfirmed(.offline), now: start)
        #expect(effects == [.finish(.failed(.offline), server: .end)])
        #expect(unconfirmed.phase == .ended(.failed(.offline)))
    }

    @Test func nothingMovesAfterTheCallEnded() {
        var machine = incoming()
        _ = machine.reduce(.ended(.busy), now: start)
        #expect(machine.reduce(.answered, now: start + 1).isEmpty)
        #expect(machine.reduce(.connected, now: start + 2).isEmpty)
        #expect(machine.reduce(.timerFired(.ring), now: start + 60).isEmpty)
        #expect(machine.phase == .ended(.busy))
    }

    @Test func aCallWithoutSystemAudioFails() {
        var silent = incoming()
        let answered = silent.reduce(.answered, now: start)
        #expect(answered.contains(.startTimer(.audioActivation, fireAt: start + 5)))
        let timedOut = silent.reduce(.timerFired(.audioActivation), now: start + 5)
        #expect(timedOut == [.finish(.failed(.other), server: .end)])

        var heard = incoming()
        _ = heard.reduce(.answered, now: start)
        #expect(heard.reduce(.audioActivated, now: start + 1) == [.cancelTimer(.audioActivation)])
        #expect(heard.reduce(.timerFired(.audioActivation), now: start + 5).isEmpty)
        #expect(heard.phase == .connecting)
    }

    @Test func startingWhileThePartnersCallRingsJoinsTheirCall() {
        var machine = outgoing()
        let partnersCall = UUID()
        let effects = machine.reduce(.registered(callID: partnersCall, answeredIncoming: true), now: start)
        #expect(machine.callID == partnersCall)
        #expect(machine.phase == .connecting)
        #expect(effects.contains(.connectMedia))

        // Their row, active with this phone's answer, keeps the call going.
        _ = machine.reduce(.liveCall(row(.active, id: partnersCall, answeredOn: deviceID)), now: start + 1)
        #expect(machine.phase == .connecting)
    }

    @Test func theRingTimerEndsAnUnansweredCall() {
        var calling = outgoing()
        _ = calling.reduce(.registered(callID: callID, answeredIncoming: false), now: start)
        #expect(calling.reduce(.timerFired(.ring), now: start + 50) == [.finish(.noAnswer, server: .end)])

        var ringing = incoming()
        #expect(ringing.reduce(.timerFired(.ring), now: start + 50) == [.finish(.missed, server: nil)])
    }

    @Test func theCallerHearsTheRingbackOnlyWhileRingingInTheCallsAudio() {
        var machine = outgoing()
        #expect(machine.reduce(.registered(callID: callID, answeredIncoming: false), now: start).isEmpty)
        #expect(machine.reduce(.audioActivated, now: start + 1).first == .ringback(isOn: true))
        #expect(machine.reduce(.audioDeactivated, now: start + 2) == [.ringback(isOn: false)])
        _ = machine.reduce(.audioActivated, now: start + 3)

        let answered = machine.reduce(.liveCall(row(.active)), now: start + 5)
        #expect(answered.first == .ringback(isOn: false))
        #expect(answered.contains(.connectMedia))

        var hungUp = outgoing()
        _ = hungUp.reduce(.audioActivated, now: start)
        #expect(hungUp.reduce(.hangUp, now: start + 1) == [.ringback(isOn: false), .finish(.hungUp, server: nil)])

        var ringing = incoming()
        #expect(ringing.reduce(.audioActivated, now: start) == [.cancelTimer(.audioActivation)])
    }

    @Test func theConnectedSoundPlaysOnceWhenTheCallFirstConnectsWithAudio() {
        var machine = incoming()
        _ = machine.reduce(.answered, now: start)
        #expect(!machine.reduce(.connected, now: start + 1).contains(.playConnectedSound))
        #expect(machine.reduce(.audioActivated, now: start + 2).contains(.playConnectedSound))

        _ = machine.reduce(.connectionLost, now: start + 30)
        #expect(!machine.reduce(.connected, now: start + 32).contains(.playConnectedSound))

        // A call that drops before its audio arrives stays quiet when it reconnects.
        var dropped = incoming()
        _ = dropped.reduce(.answered, now: start)
        _ = dropped.reduce(.connected, now: start + 1)
        _ = dropped.reduce(.connectionLost, now: start + 2)
        _ = dropped.reduce(.audioActivated, now: start + 3)
        #expect(!dropped.reduce(.connected, now: start + 4).contains(.playConnectedSound))
    }

    /// WebRTC's voice processing turns other sound down, so it waits for the ringback and the
    /// connected sound.
    @Test func webRTCsAudioRunsOnlyAfterTheConnectedSoundWhileTheCallHasAudio() {
        var machine = outgoing()
        _ = machine.reduce(.registered(callID: callID, answeredIncoming: false), now: start)
        #expect(!machine.reduce(.audioActivated, now: start + 1).contains(.mediaAudio(isOn: true)))
        #expect(!machine.reduce(.liveCall(row(.active)), now: start + 5).contains(.mediaAudio(isOn: true)))

        let connected = machine.reduce(.connected, now: start + 6)
        #expect(connected.contains(.playConnectedSound))
        #expect(connected.contains(.startTimer(.connectedSound, fireAt: start + 6 + CallMachine.connectedSoundLength)))
        #expect(!connected.contains(.mediaAudio(isOn: true)))
        #expect(machine.reduce(.timerFired(.connectedSound), now: start + 7) == [.mediaAudio(isOn: true)])

        #expect(!machine.reduce(.connectionLost, now: start + 10).contains(.mediaAudio(isOn: false)))
        #expect(machine.reduce(.audioDeactivated, now: start + 11) == [.mediaAudio(isOn: false)])
        #expect(machine.reduce(.audioActivated, now: start + 12).contains(.mediaAudio(isOn: true)))
        #expect(machine.reduce(.hangUp, now: start + 20) == [.mediaAudio(isOn: false), .finish(.hungUp, server: .end)])
    }
}
