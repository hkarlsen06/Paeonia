import Foundation

/// Screen sharing in both directions. `docs/calling-plan.md` has the decisions.
extension CallEngine {
    func startScreenShare() {
        guard let run, !run.isFinished else { return }
        run.media?.startScreenShare()
    }

    func stopScreenShare() {
        run?.media?.stopScreenShare()
    }

    func watchScreens(of media: CallMediaSession, in run: CallRun) {
        media.onPartnerScreen = { [weak self, weak run] isOn in
            guard let self, let run else { return }
            partnerScreenChanged(isOn, in: run)
        }
        media.onScreenShare = { [weak self, weak run] isOn in
            guard let self, let run else { return }
            screenShareChanged(isOn, in: run)
        }
    }

    /// This phone's share started or stopped, from the call screen, the system's indicator or
    /// the end of the call.
    func screenShareChanged(_ isOn: Bool, in run: CallRun) {
        guard run === self.run, let center, center.session?.isSharingScreen != isOn else { return }
        center.session?.isSharingScreen = isOn
        guard !run.isFinished else { return }
        // The person looks at the screen they share, so the sound leaves the earpiece.
        if isOn, CallAudio.currentRoute() == .receiver {
            CallAudio.useSpeaker(true)
            refreshAudioRoute()
        }
        reportCapabilities(of: run)
    }

    func partnerScreenChanged(_ isOn: Bool, in run: CallRun) {
        guard run === self.run, let center, center.session?.isPartnerSharingScreen != isOn else { return }
        center.session?.isPartnerSharingScreen = isOn
        updatePictureInPicture()
        if !isOn {
            // The next share may have another shape, and must not open on this one's last frame.
            partnerScreen.clear()
            center.session?.partnerScreenAspectRatio = nil
        }
        reportCapabilities(of: run)
    }

    /// The partner's shared screen changed shape, such as when they turn their phone.
    func partnerScreenSizeChanged(_ size: CGSize) {
        pictureInPicture.setVideoSize(size, of: .partnerScreen)
        guard size.width > 0, size.height > 0, let center, center.session != nil else { return }
        let ratio = size.width / size.height
        if let current = center.session?.partnerScreenAspectRatio, abs(current - ratio) < 0.01 { return }
        center.session?.partnerScreenAspectRatio = ratio
    }
}
