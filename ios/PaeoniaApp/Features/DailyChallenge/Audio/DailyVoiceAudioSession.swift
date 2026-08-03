import AVFoundation
import Foundation

nonisolated enum DailyVoiceAudioSession {
    #if compiler(>=6.4)
    private static let errorDomain = "no.paeonia.app.dailyVoice.audioSession"
    #endif

    static func configureForRecording() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
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

    static func deactivate() {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            Task.detached(priority: .utility) {
                await deactivateAsync()
            }
            return
        }
        #endif

        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    private static func activate(priority: TaskPriority) async throws {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            try await activateAsync()
            return
        }
        #endif

        try await Task.detached(priority: priority) {
            try AVAudioSession.sharedInstance().setActive(true)
        }.value
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
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

    @available(iOS 27.0, *)
    private static func deactivateAsync() async {
        let session = AVAudioSession.sharedInstance()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.deactivate(options: []) { _, _ in
                continuation.resume()
            }
        }
    }
    #endif

    #if compiler(>=6.4)
    private static func sessionError(_ message: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    #endif
}
