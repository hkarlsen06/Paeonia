import AVFoundation
import Foundation

nonisolated enum DailyVoiceAudioSession {
    private static let errorDomain = "no.paeonia.app.dailyVoice.audioSession"

    static func configureForRecording() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            // Lets the start and stop haptics play while the microphone is on. A failure
            // here only costs the haptics, so it must not block the recording.
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        }.value

        try await activate(priority: .userInitiated)
    }

    static func configureForPlayback() async {
        do {
            try await Task.detached(priority: .userInitiated) {
                try AVAudioSession.sharedInstance().setCategory(.playback)
            }.value

            try await activate(priority: .userInitiated)
        } catch {
            return
        }
    }

    /// Releases the session and tells apps we interrupted (music, podcasts) that they can
    /// resume. Used after both recording and playback.
    static func deactivate() {
        Task.detached(priority: .utility) {
            await deactivateAsync()
        }
    }

    private static func activate(priority: TaskPriority) async throws {
        try await activateAsync()
    }

    private static func activateAsync() async throws {
        let session = AVAudioSession.sharedInstance()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.activate(options: []) { activated, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if activated {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: sessionError("Audio session activation did not complete."))
                }
            }
        }
    }

    private static func deactivateAsync() async {
        let session = AVAudioSession.sharedInstance()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.deactivate(options: [.notifyOthersOnDeactivation]) { _, _ in
                continuation.resume()
            }
        }
    }

    private static func sessionError(_ message: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
