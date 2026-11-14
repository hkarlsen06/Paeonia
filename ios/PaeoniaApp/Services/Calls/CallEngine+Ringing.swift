import Foundation
import Intents
@preconcurrency import LiveCommunicationKit

/// Starting a call, and ringing for the partner's call from a VoIP push or the live query.
extension CallEngine {
    // MARK: Outgoing

    /// A call back from Recents or Siri. The handle is the partner's user id.
    func startCall(from activity: NSUserActivity) {
        let intent = activity.interaction?.intent as? INStartCallIntent
        let handle = intent?.contacts?.first?.personHandle?.value ?? ""
        Task { await startOutgoing(requestedHandle: handle) }
    }

    /// The one start path for the call buttons, Recents and Siri. `requestedHandle` is the user
    /// id the system asked to call, which must still be the partner.
    func startOutgoing(requestedHandle: String?) async {
        guard isIdle else { return }
        let partner = await CallPartner.current()
        guard isIdle else { return }
        guard let partner, requestedHandle.map({ UUID(uuidString: $0) == partner.userID }) ?? true else {
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
        let action = StartConversationAction(
            conversationUUID: callID,
            handles: [partner.handle(showsName: true)],
            isVideo: false
        )
        do {
            // The system hands the action back to `handleStart`, which calls the server.
            try await manager.perform([action])
        } catch {
            send(.failed(.other), to: run)
        }
    }

    func handleStart(_ action: StartConversationAction) {
        guard let run, run.conversationID == action.conversationUUID, run.machine.phase == .ringing else {
            action.fail()
            return
        }
        Task {
            do {
                let started = try await backend.startCall(callID: run.callID, deviceID: deviceID)
                guard run === self.run, !run.isFinished else {
                    // The person hung up while the server started the call. Stop it ringing.
                    action.fail()
                    try? await backend.endCall(callID: started.callID)
                    return
                }
                action.fulfill(dateStarted: .now)
                if started.answeredIncoming {
                    // The partner called first. Their phone sends the offer.
                    run.role = .answerer
                }
                send(.registered(callID: started.callID, answeredIncoming: started.answeredIncoming), to: run)
                reportCapabilities(of: run)
            } catch {
                action.fail()
                let isBusy = CallBackend.isServerError(error, code: CallBackend.busyCode)
                send(isBusy ? .ended(.busy) : .failed(CallFailure(error)), to: run)
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
                let handle = CallPartner.handle(userID: UUID(), name: CallPartner.privateName)
                await reportEndedCall(UUID(), handle: handle)
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

    /// Rings for the partner's call. A call the system already shows is dropped. A call that
    /// already ended, or that arrives during another call, is reported and ended at once when
    /// iOS requires a report.
    func reportIncoming(_ ring: IncomingRing, mustReport: Bool) async {
        if reportedCallIDs.contains(ring.callID) || run?.callID == ring.callID {
            return
        }
        let staleHandle = CallPartner.handle(userID: ring.callerUserID, name: CallPartner.privateName)
        guard isIdle, !finishedCallIDs.contains(ring.callID), ring.ringExpiresAt > .now else {
            if mustReport {
                await reportEndedCall(ring.callID, handle: staleHandle)
            }
            return
        }
        // Claimed before waiting, so the push and the live query cannot both report it.
        reportedCallIDs.insert(ring.callID)
        let partner = await CallPartner.current()
        guard isIdle else {
            if mustReport {
                reportedCallIDs.remove(ring.callID)
                await reportEndedCall(ring.callID, handle: staleHandle)
            }
            return
        }
        let name = ring.showsName && partner?.userID == ring.callerUserID ? partner?.name : nil
        let handle = CallPartner.handle(userID: ring.callerUserID, name: name ?? CallPartner.privateName)
        let (machine, effects) = CallMachine.incoming(
            callID: ring.callID,
            deviceID: deviceID,
            ringDeadline: ring.ringExpiresAt + Self.ringGrace
        )
        let run = begin(CallRun(machine: machine, conversationID: ring.callID, role: .answerer), effects: effects)
        do {
            try await manager.reportNewIncomingConversation(
                uuid: ring.callID,
                update: Conversation.Update(members: [handle], capabilities: [])
            )
        } catch {
            // The system did not ring, such as under a Focus that silences calls.
            send(.ended(.missed), to: run)
        }
    }

    /// Reports a call and ends it at once, for a push iOS requires a report for.
    private func reportEndedCall(_ callID: UUID, handle: Handle) async {
        reportedCallIDs.insert(callID)
        try? await manager.reportNewIncomingConversation(
            uuid: callID,
            update: Conversation.Update(members: [handle], capabilities: [])
        )
        if let conversation = manager.conversations.first(where: { $0.uuid == callID }) {
            manager.reportConversationEvent(.conversationEnded(.now, .unanswered), for: conversation)
        }
    }

    func handleJoin(_ action: JoinConversationAction) {
        guard let run, run.conversationID == action.conversationUUID,
              run.machine.direction == .incoming, run.machine.phase == .ringing
        else {
            action.fail()
            return
        }
        // Answering from a closed app before the first unlock after a restart: the sign-in
        // cannot be read, so the server cannot be told.
        guard ClerkKeychainState.current() != .locked else {
            action.fail()
            send(.failed(.other), to: run)
            return
        }
        Task {
            guard await CallAudio.microphoneAllowed() else {
                action.fail()
                send(.failed(.microphoneDenied), to: run)
                return
            }
            do {
                try await backend.answerCall(callID: run.callID, deviceID: deviceID)
                guard run === self.run, run.machine.phase == .ringing else {
                    action.fail()
                    return
                }
                action.fulfill(dateConnected: .now)
                send(.answered, to: run)
            } catch {
                // A failed answer never joins the call.
                action.fail()
                let stoppedRinging = CallBackend.isServerError(error, code: CallBackend.notRingingCode)
                send(stoppedRinging ? .ended(.missed) : .failed(CallFailure(error)), to: run)
            }
        }
    }
}
