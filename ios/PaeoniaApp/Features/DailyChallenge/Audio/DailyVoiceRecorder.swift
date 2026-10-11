import AVFoundation
import Foundation
import Observation

/// Records a short voice answer to a local m4a file. Caps the take at ~60 seconds,
/// tracks elapsed time for the UI, and supports re-recording before sending. Takes under
/// one second are thrown away. Playback and uploading are handled elsewhere, this only
/// captures.
@MainActor
@Observable
final class DailyVoiceRecorder {
    enum Phase: Equatable {
        case idle
        /// Waiting for microphone permission and the audio session. A second start is
        /// ignored while in this phase.
        case starting
        case recording
        case recorded
    }

    /// The backend rejects empty audio, so a shorter take would never finish sending.
    nonisolated static let minimumDurationMs = 1_000

    nonisolated static func isUsableTake(durationMs: Int) -> Bool {
        durationMs >= minimumDurationMs
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var recordedURL: URL?
    private(set) var recordedDurationMs: Int?
    private(set) var permissionDenied = false
    /// True when the last take was under the minimum length and got thrown away. Clears
    /// on the next start.
    private(set) var isTakeTooShort = false

    let maxDuration: TimeInterval = 60

    private var recorder: AVAudioRecorder?
    private var tickTask: Task<Void, Never>?

    func startRecording() async {
        guard phase == .idle || phase == .recorded else { return }
        let previousPhase = phase
        phase = .starting
        isTakeTooShort = false

        let granted = await AVAudioApplication.requestRecordPermission()
        // The screen can go away while the permission prompt is up.
        guard phase == .starting else { return }
        guard granted else {
            permissionDenied = true
            phase = previousPhase
            return
        }
        permissionDenied = false
        discardRecordedFile()
        recordedDurationMs = nil
        elapsed = 0

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-voice-\(UUID().uuidString).m4a")

        do {
            try await Self.activateRecordingSession()
            guard phase == .starting else {
                deactivateSession()
                return
            }

            let recorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            guard recorder.record(forDuration: maxDuration) else {
                abortStart(removing: url)
                return
            }

            self.recorder = recorder
            recordedURL = url
            phase = .recording
            PaeoniaHaptics.selection()
            startTicking()
        } catch {
            abortStart(removing: url)
        }
    }

    /// A small mono AAC file: plenty for a voice and quick to upload.
    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    func stopRecording() {
        guard phase == .recording, let recorder else { return }
        finishRecording(duration: recorder.currentTime)
    }

    /// Called when the screen goes away. A live take stops and is kept, so the caller can
    /// hand it on. A start that is still waiting is cancelled, so the microphone never
    /// turns on for a screen that is gone.
    func finishForDisappear() {
        switch phase {
        case .recording:
            stopRecording()
        case .starting:
            phase = .idle
        case .idle, .recorded:
            break
        }
    }

    /// Throws away the current take so the user can record again.
    func reset() {
        if phase == .recording {
            recorder?.stop()
            deactivateSession()
        }
        recorder = nil
        tickTask?.cancel()
        tickTask = nil
        discardRecordedFile()
        recordedDurationMs = nil
        elapsed = 0
        isTakeTooShort = false
        phase = .idle
    }

    private func finishRecording(duration: TimeInterval) {
        guard phase == .recording else { return }
        recorder?.stop()
        recorder = nil
        tickTask?.cancel()
        tickTask = nil
        deactivateSession()
        PaeoniaHaptics.selection()

        let captured = min(max(duration, elapsed), maxDuration)
        let durationMs = Int((captured * 1000).rounded())
        guard Self.isUsableTake(durationMs: durationMs) else {
            discardRecordedFile()
            recordedDurationMs = nil
            elapsed = 0
            isTakeTooShort = true
            phase = .idle
            return
        }

        recordedDurationMs = durationMs
        elapsed = captured
        phase = .recorded
    }

    /// A start that failed after the microphone was granted: drop any empty file and
    /// release the audio session so the user's music can resume.
    private func abortStart(removing url: URL) {
        try? FileManager.default.removeItem(at: url)
        deactivateSession()
        phase = .idle
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, phase == .recording, let recorder else { return }
                if recorder.isRecording {
                    elapsed = recorder.currentTime
                } else {
                    // The recorder auto-stopped at the maximum duration.
                    finishRecording(duration: elapsed)
                    return
                }
            }
        }
    }

    /// Configures and activates shared audio session without blocking the main
    /// thread on synchronous activation.
    nonisolated private static func activateRecordingSession() async throws {
        try await DailyVoiceAudioSession.configureForRecording()
    }

    /// Deactivation can block on older OS versions. Fire-and-forget:
    /// the recorder has already stopped, so nothing waits on session closing.
    private func deactivateSession() {
        DailyVoiceAudioSession.deactivate()
    }

    private func discardRecordedFile() {
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil
    }
}
