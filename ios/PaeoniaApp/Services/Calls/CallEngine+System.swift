import AVFoundation
import Foundation

/// The system's requests and audio, and what its call UI shows about the call.
extension CallEngine: CallSystemDelegate {
    func handle(_ request: CallSystemRequest) {
        switch request.action {
        case .start:
            handleStart(request)
        case .join:
            handleJoin(request)
        case .end:
            handleEnd(request)
        case let .mute(isMuted):
            handleMute(request, isMuted: isMuted)
        }
    }

    func handleTimeout(_ request: CallSystemRequest) {
        guard let run, request.conversationID == run.conversationID,
              request.action == .start || request.action == .join
        else {
            return
        }
        send(.failed(.other), to: run)
    }

    func audioActivated(_ audioSession: AVAudioSession) {
        CallAudio.didActivate(audioSession)
        CallAudio.logState("activated")
        if let run, !run.isFinished {
            send(.audioActivated, to: run)
        }
        refreshAudioRoute()
    }

    func audioDeactivated(_ audioSession: AVAudioSession) {
        CallAudio.didDeactivate(audioSession)
        if let run, !run.isFinished {
            send(.audioDeactivated, to: run)
        }
    }

    /// Follows restarts of the system's audio service, which iOS announces with
    /// `mediaServicesWereResetNotification`.
    func rebuildAudioAfterServiceRestarts() -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.audioServiceRestarted() }
        }
    }

    /// Sets the call's audio up again (`CallAudio.rebuildAfterServiceRestart`). The call counts
    /// as without audio until the engine is back or the system activates the audio again, and
    /// fails when neither happens in time, instead of running without sound.
    func audioServiceRestarted() {
        CallAudio.logState("audio service restarted")
        if let run, !run.isFinished {
            send(.audioLost, to: run)
        }
        CallAudio.rebuildAfterServiceRestart(
            sounds: sounds,
            isInCall: PaeoniaAudioSession.isCallActive
        ) { [weak self] in
            guard let self, let run, !run.isFinished else { return }
            CallAudio.logState("audio back after restart")
            send(.audioActivated, to: run)
            refreshAudioRoute()
        }
        refreshAudioRoute()
    }

    func systemReset() {
        if let run, !run.isFinished {
            run.isEndingFromSystem = true
            send(.failed(.other), to: run)
        }
    }

    /// The system keeps the call's audio until the request is fulfilled, so the ended sound
    /// plays first.
    private func handleEnd(_ request: CallSystemRequest) {
        guard let run, run.conversationID == request.conversationID, !run.isFinished else {
            return request.fulfill()
        }
        run.isEndingFromSystem = true
        send(.hangUp, to: run)
        afterGoodbye(in: run, request.fulfill)
    }

    private func handleMute(_ request: CallSystemRequest, isMuted: Bool) {
        if let run, run.conversationID == request.conversationID {
            applyMute(isMuted, in: run)
        }
        request.fulfill()
    }

    func reportProgress(of run: CallRun, from previous: CallPhase) {
        guard run.machine.direction == .outgoing else { return }
        switch (previous, run.machine.phase) {
        case (.ringing, .connecting):
            system.reportConnecting(run.conversationID)
        case (.connecting, .active):
            system.reportConnected(run.conversationID)
        case (.ringing, .active):
            system.reportConnecting(run.conversationID)
            system.reportConnected(run.conversationID)
        default:
            break
        }
    }

    func reportCapabilities(of run: CallRun) {
        guard let session = center?.session else { return }
        let hasVideo = session.isCameraOn || session.isPartnerCameraOn
            || session.isSharingScreen || session.isPartnerSharingScreen
        system.reportUpdated(run.conversationID, hasVideo: hasVideo)
    }
}
