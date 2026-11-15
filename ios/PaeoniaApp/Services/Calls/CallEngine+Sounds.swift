import Foundation

/// The call's sounds and haptics when it connects and when it ends.
extension CallEngine {
    func playConnected(haptic: Bool) {
        sounds.play(.connected)
        if haptic {
            CallHaptics.connected()
        }
    }

    /// The ended sound plays in the call's audio, which the system keeps until it hears the call
    /// ended, so the system hears it only once the sound has played (`afterGoodbye`). A call
    /// without a goodbye never connected and ends quietly.
    func sayGoodbye(_ goodbye: CallGoodbye?, in run: CallRun) {
        guard let goodbye else { return }
        if goodbye == .endedThere {
            CallHaptics.ended()
        }
        let length = sounds.play(.ended)
        run.goodbye = Task {
            try? await Task.sleep(for: length)
        }
    }

    /// Runs `body` once the ended sound has played, or at once when there is none.
    func afterGoodbye(in run: CallRun, _ body: @escaping () -> Void) {
        guard let goodbye = run.goodbye else { return body() }
        Task {
            await goodbye.value
            body()
        }
    }
}
