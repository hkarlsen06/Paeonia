import Foundation
@preconcurrency import LiveCommunicationKit
import UIKit

/// What the call screens ask for, and the call state they show.
extension CallEngine: CallEngineActions {
    func startCall() {
        Task { await startOutgoing(requestedHandle: nil) }
    }

    func answer() {
        guard let run, !run.isFinished else { return }
        requestSystem(JoinConversationAction(conversationUUID: run.conversationID)) { [weak self] in
            self?.send(.failed(.other), to: run)
        }
    }

    func decline() {
        end()
    }

    func end() {
        guard let run, !run.isFinished else { return }
        requestSystem(EndConversationAction(conversationUUID: run.conversationID)) { [weak self] in
            self?.send(.hangUp, to: run)
        }
    }

    func setMuted(_ isMuted: Bool) {
        guard let run, !run.isFinished else { return }
        let action = MuteConversationAction(conversationUUID: run.conversationID, isMuted: isMuted)
        requestSystem(action) { [weak self] in
            self?.applyMute(isMuted, in: run)
        }
    }

    func toggleSpeaker() {
        guard !isIdle else { return }
        CallAudio.useSpeaker(CallAudio.currentRoute() != .speaker)
        refreshAudioRoute()
    }

    func setCameraOn(_ isOn: Bool) {
        guard let run, !run.isFinished else { return }
        Task {
            if isOn {
                guard await CallAudio.cameraAllowed() else { return }
            }
            guard run === self.run, !run.isFinished, let center, center.session?.isCameraOn != isOn else { return }
            center.session?.isCameraOn = isOn
            run.media?.setCamera(isOn: isOn, front: center.session?.isUsingFrontCamera ?? true)
            // A video call is held away from the ear.
            if isOn, CallAudio.currentRoute() == .receiver {
                CallAudio.useSpeaker(true)
                refreshAudioRoute()
            }
            reportCapabilities(of: run)
        }
    }

    func flipCamera() {
        guard let run, !run.isFinished, let center, var session = center.session else { return }
        session.isUsingFrontCamera.toggle()
        center.session = session
        localVideo.isMirrored = session.isUsingFrontCamera
        if session.isCameraOn {
            run.media?.setCamera(isOn: true, front: session.isUsingFrontCamera)
        }
    }

    func partnerTimeZone() async -> TimeZone? {
        guard let identifier = try? await backend.partnerTimeZoneID() else { return nil }
        return TimeZone(identifier: identifier)
    }

    func makeVideoView(_ source: CallVideoSource) -> UIView {
        switch source {
        case .local:
            return localVideo.makeView()
        case .partner:
            let view = partnerVideo.makeView()
            view.onWindowChange = { [weak self] view in
                self?.pictureInPicture.sourceViewChanged(view)
            }
            return view
        }
    }

    /// Asks the system to do something to the call, so its call UI stays in step. The system
    /// hands the action back to `handle(_:)`. `ifRefused` runs when the system has no such call.
    private func requestSystem(_ action: ConversationAction, ifRefused: @escaping () -> Void) {
        Task {
            do {
                try await manager.perform([action])
            } catch {
                ifRefused()
            }
        }
    }

    func applyMute(_ isMuted: Bool, in run: CallRun) {
        guard run === self.run else { return }
        run.media?.setMuted(isMuted)
        center?.session?.isMuted = isMuted
    }

    func refreshAudioRoute() {
        guard !isIdle, let center else { return }
        let route = CallAudio.currentRoute()
        if center.session?.audioRoute != route {
            center.session?.audioRoute = route
        }
    }

    func partnerCameraChanged(_ isOn: Bool, in run: CallRun) {
        guard run === self.run, let center, center.session?.isPartnerCameraOn != isOn else { return }
        center.session?.isPartnerCameraOn = isOn
        updatePictureInPicture()
        reportCapabilities(of: run)
    }

    func updatePictureInPicture() {
        guard let session = center?.session else {
            pictureInPicture.setEnabled(false)
            return
        }
        let isTalking = switch session.phase {
        case .active, .reconnecting: true
        default: false
        }
        pictureInPicture.setEnabled(isTalking && session.isPartnerCameraOn)
    }
}
