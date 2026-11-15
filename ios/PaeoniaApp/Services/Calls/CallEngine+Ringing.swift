import Foundation
import Intents
@preconcurrency import LiveCommunicationKit

/// Starting a call, and ringing for the partner's call from a VoIP push or the live query.
extension CallEngine {
    // MARK: Outgoing

    /// A call back from Recents or Siri. The handle is the name the call showed.
    func startCall(from activity: NSUserActivity) {
        let intent = activity.interaction?.intent as? INStartCallIntent
        let handle = intent?.contacts?.first?.personHandle?.value ?? ""
        Task { await startOutgoing(requestedHandle: handle) }
    }

    /// The one start path for the call buttons, Recents and Siri. `requestedHandle` is the name
    /// the system asked to call, which must still name the partner.
    func startOutgoing(requestedHandle: String?) async {
        guard isIdle else { return }
        let partner = await CallPartner.current()
        guard isIdle else { return }
        guard let partner, requestedHandle.map(partner.answersCallBack) ?? true else {
            showEnded(.failed(.notPartner))
            return
        }
        let callID = UUID()
        let ringDeadline = Date.now + IncomingRing.defaultRingDuration + Self.ringGrace
        let (machine, effects) = CallMachine.outgoing(callID: callID, deviceID: deviceID, ringDeadline: ringDeadline)
        let run = begin(CallRun(machine: machine, conversationID: callID, role: .offerer), effects: effects)
        guard await CallAudio.microphoneAllowed() else {
            send(.failed(.microphoneDenied), to: run)
            return
        }
        guard run === self.run, !run.isFinished else { return }
        do {
            // The system hands the request back to `handleStart`, which calls the server.
            try await system.startOutgoing(callID, to: partner.handle(showsName: true))
        } catch {
            send(.failed(.other), to: run)
        }
    }

    func handleStart(_ request: CallSystemRequest) {
        guard let run, run.conversationID == request.conversationID, run.machine.phase == .ringing else {
            request.fail()
            return
        }
        Task {
            do {
                let started = try await backend.startCall(callID: run.callID, deviceID: deviceID)
                guard run === self.run, !run.isFinished else {
                    // The person hung up while the server started the call. Stop it ringing.
                    request.fail()
                    try? await backend.endCall(callID: started.callID)
                    return
                }
                request.fulfill()
                if started.answeredIncoming {
                    // The partner called first. Their phone sends the offer.
                    run.role = .answerer
                }
                send(.registered(callID: started.callID, answeredIncoming: started.answeredIncoming), to: run)
                reportCapabilities(of: run)
            } catch {
                request.fail()
                if CallBackend.isServerError(error, code: CallBackend.busyCode) {
                    send(.ended(.busy), to: run)
                } else if CallBackend.isServerError(error) {
                    send(.failed(CallFailure(error)), to: run)
                } else {
                    // The answer may be lost after the server started the call, so the partner's
                    // phone may be ringing.
                    send(.startUnconfirmed(CallFailure(error)), to: run)
                }
            }
        }
    }

    // MARK: Incoming

    func receivePush(_ ring: IncomingRing?, mustReport: Bool, completion: @escaping @Sendable () -> Void) {
        Task {
            if let ring {
                CallLockScreenPrivacy.remember(showsName: ring.showsName)
                await reportIncoming(ring, mustReport: mustReport)
            } else if mustReport {
                // Not a call push, but iOS stops VoIP pushes to an app that reports no call.
                await reportEndedCall(UUID(), handle: CallPartner.handle(name: CallPartner.privateName))
            }
            completion()
        }
    }

    func watchLiveCalls() {
        Task {
            while !Task.isCancelled {
                for await result in backend.liveCalls() {
                    if case let .value(call) = result {
                        await receiveLiveCall(call)
                    }
                }
                // The stream ends when the server refuses, such as without access. Try again later.
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func receiveLiveCall(_ call: LiveCall?) async {
        if let run, !run.isFinished {
            send(.liveCall(call), to: run)
            return
        }
        guard let call, call.state == .ringing, call.ringExpiresAt > .now,
              let partner = await CallPartner.current(), call.callerUserID == partner.userID
        else {
            return
        }
        let ring = IncomingRing(
            callID: call.callID,
            callerUserID: call.callerUserID,
            ringExpiresAt: call.ringExpiresAt,
            showsName: CallLockScreenPrivacy.showsName
        )
        await reportIncoming(ring, mustReport: false)
    }

    /// Rings for the partner's call, reported to the system before anything slow runs. A call the
    /// system already shows is dropped. A call that already ended, or that arrives during another
    /// call, is reported and ended at once when iOS requires a report.
    func reportIncoming(_ ring: IncomingRing, mustReport: Bool) async {
        if let run, !run.isFinished, run.callID == ring.callID || run.conversationID == ring.callID {
            return
        }
        guard isIdle, !reportedCallIDs.contains(ring.callID), !finishedCallIDs.contains(ring.callID),
              ring.ringExpiresAt > .now
        else {
            if mustReport {
                await reportEndedCall(ring.callID, handle: CallPartner.handle(name: CallPartner.privateName))
            }
            return
        }
        reportedCallIDs.insert(ring.callID)
        // The store cannot be read on a locked phone, and the report cannot wait for it.
        let partner = CallPartner.cached
        let name = ring.showsName && partner?.userID == ring.callerUserID ? partner?.name : nil
        let handle = CallPartner.handle(name: name ?? CallPartner.privateName)
        let (machine, effects) = CallMachine.incoming(
            callID: ring.callID,
            deviceID: deviceID,
            ringDeadline: ring.ringExpiresAt + Self.ringGrace
        )
        let run = begin(CallRun(machine: machine, conversationID: ring.callID, role: .answerer), effects: effects)
        do {
            try await system.reportIncoming(ring.callID, from: handle)
        } catch {
            // The system did not ring, such as under a Focus that silences calls.
            send(.ended(.missed), to: run)
        }
    }

    /// Reports a call and ends it at once, for a push iOS requires a report for.
    private func reportEndedCall(_ callID: UUID, handle: Handle) async {
        reportedCallIDs.insert(callID)
        try? await system.reportIncoming(callID, from: handle)
        system.reportEnded(callID, reason: .missed)
    }

    func handleJoin(_ request: CallSystemRequest) {
        guard let run, run.conversationID == request.conversationID,
              run.machine.direction == .incoming, run.machine.phase == .ringing
        else {
            request.fail()
            return
        }
        // Answering from a closed app before the first unlock after a restart: the sign-in
        // cannot be read, so the server cannot be told.
        guard ClerkKeychainState.current() != .locked else {
            request.fail()
            send(.failed(.other), to: run)
            return
        }
        Task {
            guard await CallAudio.microphoneAllowed() else {
                request.fail()
                send(.failed(.microphoneDenied), to: run)
                return
            }
            do {
                try await backend.answerCall(callID: run.callID, deviceID: deviceID)
                guard run === self.run, run.machine.phase == .ringing else {
                    // The call ended here while the server took the answer, so end it there too.
                    request.fail()
                    try? await backend.endCall(callID: run.callID)
                    return
                }
                request.fulfill()
                send(.answered, to: run)
            } catch {
                // A failed answer never joins the call.
                request.fail()
                let stoppedRinging = CallBackend.isServerError(error, code: CallBackend.notRingingCode)
                send(stoppedRinging ? .ended(.missed) : .failed(CallFailure(error)), to: run)
            }
        }
    }
}
