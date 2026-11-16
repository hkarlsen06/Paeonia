import Foundation

/// How well the call runs: a weak connection, the partner's video standing still, and this
/// phone's heat and battery.
extension CallEngine {
    func dismissCameraOffSuggestion() {
        guard let run, let suggestion = center?.session?.cameraOffSuggestion else { return }
        run.dismissedCameraOffSuggestions.insert(suggestion)
        updateCameraOffSuggestion(in: run)
    }

    func watchConnection(of media: CallMediaSession, in run: CallRun) {
        media.onWeakConnection = { [weak self, weak run] side in
            guard let self, let run, run === self.run, let center, center.session?.weakConnection != side else {
                return
            }
            center.session?.weakConnection = side
        }
    }

    func partnerVideoStallChanged(_ isStalled: Bool) {
        guard let center, center.session?.isPartnerVideoStalled != isStalled else { return }
        center.session?.isPartnerVideoStalled = isStalled
    }

    func watchPower(of run: CallRun) {
        run.power = CallDevicePower { [weak self, weak run] state in
            guard let self, let run, run === self.run else { return }
            run.media?.setHeat(state.heat)
            updateCameraOffSuggestion(in: run)
        }
    }

    func updateCameraOffSuggestion(in run: CallRun) {
        guard run === self.run, let center, let session = center.session, let power = run.power else { return }
        let suggestion = power.state.cameraOffSuggestion(
            isCameraOn: session.isCameraOn,
            dismissed: run.dismissedCameraOffSuggestions
        )
        if session.cameraOffSuggestion != suggestion {
            center.session?.cameraOffSuggestion = suggestion
        }
    }
}
