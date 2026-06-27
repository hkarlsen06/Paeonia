import AVFoundation
import Foundation
import Observation

/// Records a short voice answer to a local m4a file. Caps the take at ~60 seconds,
/// tracks elapsed time for the UI, and supports re-recording before sending. Playback
/// and uploading are handled elsewhere — this only captures.
@MainActor
@Observable
final class DailyVoiceRecorder {
    enum Phase: Equatable {
        case idle
        case recording
        case recorded
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var recordedURL: URL?
    private(set) var recordedDurationMs: Int?
    private(set) var permissionDenied = false

    let maxDuration: TimeInterval = 60

    private var recorder: AVAudioRecorder?
    private var tickTask: Task<Void, Never>?

    func startRecording() async {
        guard phase != .recording else { return }

        guard await AVAudioApplication.requestRecordPermission() else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        discardRecordedFile()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: maxDuration) else {
                phase = .idle
                return
            }

            self.recorder = recorder
            recordedURL = url
            elapsed = 0
            phase = .recording
            startTicking()
        } catch {
            phase = .idle
        }
    }

    func stopRecording() {
        guard phase == .recording, let recorder else { return }
        finishRecording(duration: recorder.currentTime)
    }

    /// Throws away the current take so the user can record again.
    func reset() {
        if phase == .recording {
            recorder?.stop()
            deactivateSession()
        }
        tickTask?.cancel()
        tickTask = nil
        discardRecordedFile()
        recordedDurationMs = nil
        elapsed = 0
        phase = .idle
    }

    private func finishRecording(duration: TimeInterval) {
        guard phase == .recording else { return }
        recorder?.stop()
        tickTask?.cancel()
        tickTask = nil
        deactivateSession()

        let captured = min(max(duration, elapsed), maxDuration)
        recordedDurationMs = Int((captured * 1000).rounded())
        elapsed = captured
        phase = .recorded
    }

    private func startTicking() {
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard phase == .recording, let recorder else { return }
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

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func discardRecordedFile() {
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil
    }
}
