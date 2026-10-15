import AVFoundation
import Foundation
import os

/// Every change to the shared audio session goes through one actor, so a release
/// that is still waiting can never land on top of the next recording or playback.
nonisolated enum DailyVoiceAudioSession {
    private static let errorDomain = "no.paeonia.app.dailyVoice.audioSession"
    private static let gate = Gate()
    /// Counts requests in the order callers make them. Stamped when the caller asks,
    /// not when the actor gets to it.
    private static let requests = OSAllocatedUnfairLock(initialState: 0)

    static func configureForRecording() async throws {
        // Asking for the session cancels any release still waiting (see `deactivate`).
        _ = nextRequest()
        try await gate.activate { session in
            // Ducking lowers the person's music while they record instead of pausing it.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            // Lets the start and stop haptics play while the microphone is on. A failure
            // here only costs the haptics, so it must not block the recording.
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        }
    }

    static func configureForPlayback() async {
        _ = nextRequest()
        try? await gate.activate { session in
            // Ducks the person's music under the voice note instead of pausing it.
            try session.setCategory(.playback, options: [.duckOthers])
        }
    }

    /// Releases the session, tells apps we ducked (music, podcasts) to come back up, and
    /// returns to the app's resting `.ambient` session. Used after both recording and
    /// playback. Nothing waits for it. A recording or playback that asks for the session
    /// after this call makes the release unnecessary, and the release is skipped.
    static func deactivate() {
        let request = nextRequest()
        Task.detached(priority: .utility) {
            await gate.deactivate(request: request)
        }
    }

    private static func nextRequest() -> Int {
        requests.withLock {
            $0 += 1
            return $0
        }
    }

    private static func isLatest(_ request: Int) -> Bool {
        requests.withLock { $0 } == request
    }

    private actor Gate {
        func activate(configure: @Sendable (AVAudioSession) throws -> Void) async throws {
            let session = AVAudioSession.sharedInstance()
            try configure(session)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.activate(options: []) { activated, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if activated {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: DailyVoiceAudioSession.sessionError(
                            "Audio session activation did not complete."
                        ))
                    }
                }
            }
        }

        func deactivate(request: Int) async {
            guard DailyVoiceAudioSession.isLatest(request) else { return }
            let session = AVAudioSession.sharedInstance()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.deactivate(options: [.notifyOthersOnDeactivation]) { _, _ in
                    continuation.resume()
                }
            }
            // A new request may have arrived while the release ran. Leave the
            // category it set.
            guard DailyVoiceAudioSession.isLatest(request) else { return }
            PaeoniaAudioSession.useAmbient()
        }
    }

    fileprivate static func sessionError(_ message: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
