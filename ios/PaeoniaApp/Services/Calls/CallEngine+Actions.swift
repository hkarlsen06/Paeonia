import Foundation
import UIKit

/// What the call screens ask for, and the call state they show.
extension CallEngine: CallEngineActions {
    func startCall() {
        Task { await startOutgoing(requestedHandle: nil) }
    }

    /// Opens the full call screen and joins the call through the system, which first hears of a
    /// call that rang only inside the app.
    func answer() {
        guard let run, !run.isFinished else { return }
        run.quality.noteAnswer(at: .now)
        center?.presentation = .full
        let unreportedHandle = run.takeUnreportedRing()
        requestSystem { system in
            if let unreportedHandle {
                try await system.reportIncoming(run.conversationID, from: unreportedHandle)
            }
            try await system.requestJoin(run.conversationID)
        } ifRefused: { [weak self] in
            self?.send(.failed(.other), to: run)
        }
    }

    /// A call that rang only inside the app ends here, because the system has nothing to end.
    func decline() {
        guard let run, !run.isFinished else { return }
        if run.takeUnreportedRing() != nil {
            send(.hangUp, to: run)
        } else {
            end()
        }
    }

    func end() {
        guard let run, !run.isFinished else { return }
        requestSystem { try await $0.requestEnd(run.conversationID) } ifRefused: { [weak self] in
            self?.send(.hangUp, to: run)
        }
    }

    func setMuted(_ isMuted: Bool) {
        guard let run, !run.isFinished else { return }
        requestSystem { try await $0.requestMute(run.conversationID, isMuted: isMuted) } ifRefused: { [weak self] in
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
            updateCameraOffSuggestion(in: run)
        }
    }

    func flipCamera() {
        guard let run, !run.isFinished, let center, var session = center.session else { return }
        session.isUsingFrontCamera.toggle()
        center.session = session
        if session.isCameraOn {
            run.media?.setCamera(isOn: true, front: session.isUsingFrontCamera)
        }
    }

    func setBackCameraZoom(_ factor: Double) {
        if let applied = run?.media?.setBackCameraZoom(factor) {
            center?.backCameraZoom?.factor = applied
        }
    }

    /// Waits a moment for a fresh read, so a slow network never holds up the call. The read
    /// keeps going and updates `knownPartnerTimeZone` for the next call.
    func partnerTimeZone() async -> TimeZone? {
        refreshCallContext()
        let deadline = ContinuousClock.now + .milliseconds(1_500)
        // Waiting on the read's task cannot stop early, so check every 50 ms.
        while partnerTimeZoneRefresh != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return knownPartnerTimeZone
    }

    func refreshCallContext() {
        Task { _ = await CallPartner.current() }
        guard partnerTimeZoneRefresh == nil else { return }
        partnerTimeZoneRefresh = Task {
            defer { partnerTimeZoneRefresh = nil }
            do {
                knownPartnerTimeZone = try await backend.partnerTimeZoneID().flatMap(TimeZone.init(identifier:))
            } catch {
                // Keep the last zone the server sent.
            }
        }
    }

    func makeVideoView(_ source: CallVideoSource) -> UIView {
        switch source {
        case .local:
            return localVideo.makeView()
        case .partner:
            let view = partnerVideo.makeView()
            pictureInPicture.track(view)
            return view
        case .partnerScreen:
            let view = partnerScreen.makeView()
            pictureInPicture.track(view)
            return view
        }
    }

    /// Asks the system to do something to the call, so its call UI stays in step. The system
    /// hands the request back to `handle(_:)`. `ifRefused` runs when the system has no such call.
    private func requestSystem(
        _ request: @escaping (any CallSystem) async throws -> Void,
        ifRefused: @escaping () -> Void
    ) {
        Task {
            do {
                try await request(system)
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
        CallAudio.logState("route refresh")
        let route = CallAudio.currentRoute()
        if center.session?.audioRoute != route {
            center.session?.audioRoute = route
        }
    }

    func partnerCameraChanged(_ state: CallCameraState, in run: CallRun) {
        guard run === self.run, let center, center.session?.partnerCamera != state else { return }
        center.session?.partnerCamera = state
        // A paused camera shows its own symbol instead of a blur.
        partnerVideo.watchForStalls(state == .on)
        if state == .off {
            partnerVideo.forgetLatestFrame()
        }
        updatePictureInPicture()
        reportCapabilities(of: run)
    }

    /// The partner's frames changed size, such as when they turn their phone. A new resolution in
    /// the same shape changes nothing on screen.
    func partnerVideoSizeChanged(_ size: CGSize) {
        pictureInPicture.setVideoSize(size, of: .partner)
        guard size.width > 0, size.height > 0, let center, center.session != nil else { return }
        let ratio = size.width / size.height
        if let current = center.session?.partnerVideoAspectRatio, abs(current - ratio) < 0.01 { return }
        center.session?.partnerVideoAspectRatio = ratio
    }

    /// This phone's camera frames changed shape, such as when the person turns the phone.
    func localVideoSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, let center, center.session != nil else { return }
        let ratio = size.width / size.height
        if let current = center.session?.localVideoAspectRatio, abs(current - ratio) < 0.01 { return }
        center.session?.localVideoAspectRatio = ratio
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
        // The partner's shared screen is what a person wants to keep watching in another app.
        pictureInPicture.show(session.isPartnerSharingScreen ? .partnerScreen : .partner)
        pictureInPicture.setEnabled(isTalking && (session.isPartnerCameraOn || session.isPartnerSharingScreen))
    }
}
