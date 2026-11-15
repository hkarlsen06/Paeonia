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
        if let run, !run.isFinished {
            useSpeakerAtStart(of: run)
            send(.audioActivated, to: run)
        }
        refreshAudioRoute()
    }

    /// Every call starts on the speaker, unless AirPods, a headset or a car has the sound. Only
    /// the call's first activation picks, so a later one keeps what the person chose.
    private func useSpeakerAtStart(of run: CallRun) {
        guard !run.hasPickedStartingRoute else { return }
        run.hasPickedStartingRoute = true
        if CallAudio.currentRoute() == .receiver {
            CallAudio.useSpeaker(true)
        }
    }

    func audioDeactivated(_ audioSession: AVAudioSession) {
        CallAudio.didDeactivate(audioSession)
        if let run, !run.isFinished {
            send(.audioDeactivated, to: run)
        }
    }

    func systemReset() {
        if let run, !run.isFinished {
            run.isEndingFromSystem = true
            send(.failed(.other), to: run)
        }
    }

    private func handleEnd(_ request: CallSystemRequest) {
        if let run, run.conversationID == request.conversationID, !run.isFinished {
            run.isEndingFromSystem = true
            send(.hangUp, to: run)
        }
        request.fulfill()
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
        default:
            break
        }
    }

    func reportCapabilities(of run: CallRun) {
        guard let session = center?.session else { return }
        system.reportUpdated(run.conversationID, hasVideo: session.isCameraOn || session.isPartnerCameraOn)
    }
}
