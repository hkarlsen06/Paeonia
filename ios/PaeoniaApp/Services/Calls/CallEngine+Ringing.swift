import AVFAudio
import Foundation
import Intents
@preconcurrency import LiveCommunicationKit
import UIKit

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
            try await system.startOutgoing(callID, to: partner.handle)
        } catch {
            send(.failed(.other), to: run)
        }
    }

    /// Reads the server's row every `ringWatchInterval` while the call rings, once the server has
    /// it. The live query reports an answer or a cancel at once, but its socket can stay on a
    /// network the phone left. After Wi-Fi turned off, a caller kept ringing for 18 seconds after
    /// the answer. Each read opens on the current network.
    func updateRingWatch(_ run: CallRun) {
        let isRinging = run.machine.phase == .ringing && run.machine.isRegistered
        guard isRinging != (run.ringWatch != nil) else { return }
        guard isRinging else {
            run.ringWatch?.cancel()
            run.ringWatch = nil
            return
        }
        run.ringWatch = Task { [weak self, weak run, backend] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.ringWatchInterval)
                let row: LiveCall?
                do {
                    row = try await backend.liveCall()
                } catch {
                    continue
                }
                guard !Task.isCancelled, let self, let run else { return }
                send(.liveCall(row), to: run)
            }
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

    /// PushKit checks that the call was reported when `completion` runs, not when its delegate
    /// method returns, so `completion` comes only after the report. `docs/calling-plan.md`
    /// ("Mistakes other teams made") says how that was checked.
    func receivePush(_ ring: IncomingRing?, mustReport: Bool, completion: @escaping @Sendable () -> Void) {
        Task {
            if let ring {
                await reportIncoming(ring, mustReport: mustReport)
            } else if mustReport {
                // Not a call push, but iOS stops VoIP pushes to an app that reports no call.
                await reportEndedCall(UUID(), handle: CallPartner.handle(name: CallPartner.neutralName))
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
            ringExpiresAt: call.ringExpiresAt
        )
        await reportIncoming(ring, mustReport: false)
    }

    /// Rings for the partner's call. While Paeonia is open on screen and iOS does not require a
    /// report, it rings inside the app and the system hears of the call only when the person
    /// answers or leaves the app. Otherwise the call is reported to the system before anything
    /// slow runs. A call that already rings is dropped, unless iOS requires a report for it. A call
    /// that already ended, or that arrives during another call, is reported and ended at once when
    /// iOS requires a report.
    func reportIncoming(_ ring: IncomingRing, mustReport: Bool) async {
        if let run, !run.isFinished, run.callID == ring.callID || run.conversationID == ring.callID {
            if mustReport {
                // iOS ends an app that does not report such a push.
                await handRingToSystem(run)
            }
            return
        }
        guard isIdle, !reportedCallIDs.contains(ring.callID), !finishedCallIDs.contains(ring.callID),
              ring.ringExpiresAt > .now
        else {
            if mustReport {
                await reportEndedCall(ring.callID, handle: CallPartner.handle(forCaller: ring.callerUserID))
            }
            return
        }
        reportedCallIDs.insert(ring.callID)
        let handle = CallPartner.handle(forCaller: ring.callerUserID)
        let (machine, effects) = CallMachine.incoming(
            callID: ring.callID,
            deviceID: deviceID,
            ringDeadline: ring.ringExpiresAt + Self.ringGrace
        )
        let ringsInApp = !mustReport && UIApplication.shared.applicationState == .active
        let run = begin(
            CallRun(machine: machine, conversationID: ring.callID, role: .answerer),
            effects: effects,
            ringsInApp: ringsInApp
        )
        if ringsInApp {
            run.ringInApp(from: handle)
        } else {
            await reportToSystem(run, from: handle)
        }
    }

    /// Hands a ring inside the app to the system once the app is in the background. Not when the
    /// app only stops being active, as under Control Center, where the ring in the app still shows.
    func handRingsToSystemInBackground() -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let run = self.run, !run.isFinished else { return }
                Task { await self.handRingToSystem(run) }
            }
        }
    }

    /// Hands a ring that shows only inside the app to the system, which rings from now on. Does
    /// nothing once the system knows the call.
    func handRingToSystem(_ run: CallRun) async {
        guard run === self.run, let handle = run.takeUnreportedRing() else { return }
        center?.session?.ringsInApp = false
        // An answer on the system call UI then opens the full call screen, as for any system ring.
        center?.presentation = .full
        await reportToSystem(run, from: handle)
    }

    private func reportToSystem(_ run: CallRun, from handle: Handle) async {
        do {
            try await system.reportIncoming(run.conversationID, from: handle)
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
        run.quality.noteAnswer(at: .now)
        // Answering from a closed app before the first unlock after a restart: the sign-in
        // cannot be read, so the server cannot be told.
        guard ClerkKeychainState.current() != .locked else {
            request.fail()
            send(.failed(.other), to: run)
            return
        }
        // iOS cannot ask for the microphone on a locked screen or in the background, so only a
        // refusal the person already gave stops the answer.
        let microphone = CallAudio.microphonePermission
        guard microphone != .denied else {
            request.fail()
            send(.failed(.microphoneDenied), to: run)
            return
        }
        Task {
            do {
                try await backend.answerCall(callID: run.callID, deviceID: deviceID)
                guard run === self.run, run.machine.phase == .ringing else {
                    // The call ended here while the server took the answer, so end it there too.
                    request.fail()
                    try? await backend.endCall(callID: run.callID)
                    return
                }
                request.fulfill()
                // The ring is over. A ring that showed inside the app goes on as any other call.
                center?.session?.ringsInApp = false
                send(.answered, to: run)
                if microphone != .granted {
                    askForMicrophone(during: run)
                }
            } catch {
                // A failed answer never joins the call.
                request.fail()
                let stoppedRinging = CallBackend.isServerError(error, code: CallBackend.notRingingCode)
                send(stoppedRinging ? .ended(.missed) : .failed(CallFailure(error)), to: run)
            }
        }
    }

    /// Asks for the microphone without holding up the call. iOS shows the question once the
    /// person opens the app, and until they answer the partner cannot hear them.
    private func askForMicrophone(during run: CallRun) {
        center?.session?.isWaitingForMicrophone = true
        Task {
            let isAllowed = await CallAudio.microphoneAllowed()
            guard run === self.run, !run.isFinished else { return }
            center?.session?.isWaitingForMicrophone = false
            if isAllowed {
                CallAudio.restartForMicrophone()
            } else {
                send(.failed(.microphoneDenied), to: run)
            }
        }
    }
}
