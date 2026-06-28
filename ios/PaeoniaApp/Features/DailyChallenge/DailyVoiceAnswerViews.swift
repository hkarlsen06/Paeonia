import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Plays a short voice answer with a simple progress scrubber. No autoplay and no
/// lock-screen metadata — playback only starts on an explicit tap.
@MainActor
@Observable
final class DailyVoicePlayer {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var tickTask: Task<Void, Never>?

    func load(url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            progress = 0
        } catch {
            player = nil
        }
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            // Activate the session off the main thread (it blocks), then start.
            Task { @MainActor in
                await Self.activatePlaybackSession()
                guard let player = self.player, !player.isPlaying else { return }
                player.play()
                isPlaying = true
                startTicking()
            }
        }
    }

    /// Configures and activates playback without blocking the main thread on
    /// synchronous activation.
    nonisolated private static func activatePlaybackSession() async {
        await DailyVoiceAudioSession.configureForPlayback()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        tickTask?.cancel()
        tickTask = nil
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        progress = 0
        tickTask?.cancel()
        tickTask = nil
    }

    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        player.currentTime = fraction * duration
        progress = fraction
    }

    private func startTicking() {
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let player else { return }
                if player.isPlaying {
                    progress = duration > 0 ? player.currentTime / duration : 0
                    try? await Task.sleep(for: .milliseconds(100))
                } else {
                    // Reached the end: reset to the start so it can be replayed.
                    isPlaying = false
                    progress = 0
                    player.currentTime = 0
                    return
                }
            }
        }
    }
}

/// Where a playback view gets its audio: a local staged file (the composer preview)
/// or a revealed answer's media asset (downloaded and cached).
enum DailyVoiceSource: Equatable {
    case data(Data)
    case mediaAsset(UUID)
}

/// Tap-to-play voice playback with a scrubber and a running time. Used both for the
/// composer preview (local bytes) and the revealed answer (downloaded bytes).
struct DailyVoicePlaybackView: View {
    let source: DailyVoiceSource
    var fallbackDurationMs: Int?
    var fetch: (UUID) async -> Data? = { await DailyAnswerMediaImageProviderFactory.shared?.imageData(for: $0) }

    @State private var player = DailyVoicePlayer()
    @State private var didFail = false

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button(action: player.togglePlay) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.paeoniaAccentPrimary)
            }
            .buttonStyle(.plain)
            .disabled(didFail)
            .accessibilityLabel(Text(.dailyChallengeVoicePlay))

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                )
            )
            .tint(.paeoniaAccentPrimary)

            Text(timeLabel)
                .font(PaeoniaTypography.caption.monospacedDigit())
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .task(id: source) { await load() }
    }

    private var timeLabel: String {
        let total = player.duration > 0 ? player.duration : Double(fallbackDurationMs ?? 0) / 1000
        let current = player.duration > 0 ? player.progress * player.duration : 0
        return "\(formatted(current)) / \(formatted(total))"
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func load() async {
        didFail = false
        let data: Data?
        switch source {
        case let .data(bytes):
            data = bytes
        case let .mediaAsset(id):
            data = await fetch(id)
        }

        guard let data else {
            didFail = true
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-voice-play-\(UUID().uuidString).m4a")
        do {
            try data.write(to: url, options: [.atomic])
            player.load(url: url)
        } catch {
            didFail = true
        }
    }
}

/// Records a voice answer: tap to start, tap to stop (auto-stops at the cap). Once a
/// take exists the parent swaps in the playback preview, so this view only owns the
/// idle and recording states.
struct DailyVoiceRecorderView: View {
    let onRecorded: (URL, Int) -> Void

    @State private var recorder = DailyVoiceRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.dailyChallengeVoiceLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            Button(action: toggle) {
                HStack(spacing: PaeoniaSpacing.space12) {
                    Image(systemName: recorder.phase == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(recorder.phase == .recording ? Color.paeoniaError : Color.paeoniaAccentPrimary)
                        .accessibilityHidden(true)

                    Text(recorder.phase == .recording ? recordingLabel : startLabel)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Spacer(minLength: 0)
                }
                .padding(PaeoniaSpacing.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.paeoniaSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            }
            .buttonStyle(.plain)

            if recorder.permissionDenied {
                Text(.dailyChallengeVoicePermissionDenied)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: recorder.phase) { _, phase in
            if phase == .recorded, let url = recorder.recordedURL, let durationMs = recorder.recordedDurationMs {
                onRecorded(url, durationMs)
            }
        }
    }

    private var startLabel: String {
        String(localized: .dailyChallengeVoiceRecord)
    }

    private var recordingLabel: String {
        let value = Int(recorder.elapsed.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func toggle() {
        switch recorder.phase {
        case .recording:
            recorder.stopRecording()
        case .idle, .recorded:
            Task { await recorder.startRecording() }
        }
    }
}
