import Foundation

/// Screen sharing in both directions. `docs/calling-plan.md` has the decisions.
extension CallEngine {
    /// How long the call says a share did not start.
    static let screenShareFailureLinger: Duration = .seconds(4)

    func startScreenShare() {
        guard let run, !run.isFinished else { return }
        if center?.session?.screenShare == .failed { screenShareChanged(.off, in: run) }
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
        media.onScreenShare = { [weak self, weak run] share in
            guard let self, let run else { return }
            screenShareChanged(share, in: run)
        }
    }

    /// This phone's share is starting, on, off or did not start, from the call screen, the
    /// system's indicator or the end of the call. A failure shows for a moment, then the share is
    /// off again.
    func screenShareChanged(_ share: CallScreenShare, in run: CallRun) {
        guard run === self.run, let center, let session = center.session, session.screenShare != share else { return }
        let wasSharing = session.isSharingScreen
        center.session?.screenShare = share
        run.screenShareFailure?.cancel()
        run.screenShareFailure = nil
        guard !run.isFinished else { return }
        if share == .failed {
            run.screenShareFailure = Task { [weak self, weak run] in
                try? await Task.sleep(for: Self.screenShareFailureLinger)
                guard !Task.isCancelled, let self, let run else { return }
                screenShareChanged(.off, in: run)
            }
        }
        guard wasSharing != (share == .on) else { return }
        // The person looks at the screen they share, so the sound leaves the earpiece.
        if share == .on, CallAudio.currentRoute() == .receiver {
            CallAudio.useSpeaker(true)
            refreshAudioRoute()
        }
        reportCapabilities(of: run)
    }

    func partnerScreenChanged(_ isOn: Bool, in run: CallRun) {
        guard run === self.run, let center, center.session?.isPartnerSharingScreen != isOn else { return }
        center.session?.isPartnerSharingScreen = isOn
        // The partner's phone sends its last frame again every second while their screen is still,
        // so frames that stop mean the stream stalled.
        partnerScreen.watchForStalls(isOn)
        updatePictureInPicture()
        if !isOn {
            // The next share may have another shape, and must not open on this one's last frame.
            partnerScreen.clear()
            center.session?.partnerScreenAspectRatio = nil
        }
        reportCapabilities(of: run)
    }

    func partnerScreenStallChanged(_ isStalled: Bool) {
        guard let center, center.session?.isPartnerScreenStalled != isStalled else { return }
        center.session?.isPartnerScreenStalled = isStalled
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
