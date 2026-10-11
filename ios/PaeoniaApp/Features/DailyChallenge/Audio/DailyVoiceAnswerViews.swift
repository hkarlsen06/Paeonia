import AVFoundation
import Foundation
import Observation
import SwiftUI
import UIKit

/// Plays a short voice answer with a simple progress scrubber. No autoplay and no
/// lock-screen metadata, so playback only starts on an explicit tap. Only one clip plays
/// at a time: starting one pauses the other.
@MainActor
@Observable
final class DailyVoicePlayer {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var duration: TimeInterval = 0

    /// How close to the end a stopped player must be to count as finished. The progress
    /// tick runs every 100 ms, so the last sample can be a little short of the end.
    private static let endTolerance: TimeInterval = 0.25
    /// The player that is playing now, so starting another one can pause it.
    private static weak var current: DailyVoicePlayer?

    private var player: AVAudioPlayer?
    private var tickTask: Task<Void, Never>?

    var isLoaded: Bool { player != nil }

    /// Builds the player from the bytes, so the duration is known straight away and no
    /// file is written. Returns false when the bytes are not playable audio.
    func load(data: Data) -> Bool {
        stop()
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue)
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            return true
        } catch {
            return false
        }
    }

    func togglePlay() {
        if player?.isPlaying == true {
            pause()
        } else {
            // Activate the session off the main thread (it blocks), then start.
            Task { @MainActor [weak self] in
                await Self.activatePlaybackSession()
                guard let self, let player, !player.isPlaying else { return }
                // Handing over from another clip keeps the session, so the music app
                // is not told to resume in between.
                if let other = Self.current, other !== self {
                    other.halt(releasingSession: false)
                }
                Self.current = self
                progress = duration > 0 ? player.currentTime / duration : 0
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
        halt(releasingSession: true)
    }

    /// Stops playback, rewinds, and drops the loaded audio.
    func stop() {
        halt(releasingSession: true)
        player?.currentTime = 0
        player = nil
        duration = 0
        progress = 0
    }

    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        player.currentTime = fraction * duration
        progress = fraction
    }

    /// Pauses in place. Releasing the session lets the user's music resume, but only
    /// when this player was the one playing.
    private func halt(releasingSession: Bool) {
        let wasPlaying = isPlaying
        player?.pause()
        isPlaying = false
        tickTask?.cancel()
        tickTask = nil
        if Self.current === self {
            Self.current = nil
        }
        if releasingSession, wasPlaying {
            DailyVoiceAudioSession.deactivate()
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            var lastTime: TimeInterval = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let player else { return }
                if player.isPlaying {
                    lastTime = player.currentTime
                    progress = duration > 0 ? lastTime / duration : 0
                } else {
                    playbackStopped(at: max(lastTime, player.currentTime))
                    return
                }
            }
        }
    }

    /// The player stopped by itself. Either the clip ran to the end, or the system
    /// paused it (a phone call, Siri). Only a finished clip rewinds, so an interrupted
    /// one resumes where it was.
    private func playbackStopped(at time: TimeInterval) {
        halt(releasingSession: true)
        if duration > 0, time >= duration - Self.endTolerance {
            player?.currentTime = 0
            progress = 0
        } else {
            progress = duration > 0 ? time / duration : 0
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40
    @State private var player = DailyVoicePlayer()
    @State private var loadState = LoadState.loading
    @State private var attempt = 0

    private enum LoadState {
        case loading
        case loaded
        case failed
    }

    /// Reloads when the source changes or the user taps Try again.
    private struct LoadRequest: Equatable {
        let source: DailyVoiceSource
        let attempt: Int
    }

    var body: some View {
        Group {
            if loadState == .failed {
                failedContent
            } else {
                playerContent
            }
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .task(id: LoadRequest(source: source, attempt: attempt)) { await load() }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var playerContent: some View {
        // At accessibility text sizes the time moves under the slider, so the slider
        // keeps enough width to drag.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space12) {
                playButton
                slider
                if !dynamicTypeSize.isAccessibilitySize {
                    timeText
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                timeText
            }
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.dailyChallengeVoiceLoadFailed)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                attempt += 1
            } label: {
                Text(.dailyChallengeVoiceRetry)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        }
    }

    private var playButton: some View {
        Button(action: player.togglePlay) {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.paeoniaAccentPrimary)
                .opacity(isDownloading ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!player.isLoaded)
        .overlay {
            if isDownloading {
                ProgressView()
            }
        }
        .accessibilityLabel(Text(player.isPlaying ? .dailyChallengeVoicePause : .dailyChallengeVoicePlay))
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { player.progress },
                set: { player.seek(to: $0) }
            )
        )
        .tint(.paeoniaAccentPrimary)
        .disabled(!player.isLoaded)
        .accessibilityLabel(Text(.dailyChallengeVoicePosition))
        .accessibilityValue(Text(.dailyChallengeVoiceTimeOfTotal(voiceClock(currentSeconds), voiceClock(totalSeconds))))
    }

    /// The slider already speaks the time, so VoiceOver skips this label.
    private var timeText: some View {
        Text(verbatim: "\(voiceClock(currentSeconds)) / \(voiceClock(totalSeconds))")
            .font(PaeoniaTypography.caption.monospacedDigit())
            .foregroundStyle(.paeoniaTextSecondary)
            .accessibilityHidden(true)
    }

    private var isDownloading: Bool {
        if case .mediaAsset = source {
            return loadState == .loading
        }
        return false
    }

    private var totalSeconds: TimeInterval {
        player.duration > 0 ? player.duration : Double(fallbackDurationMs ?? 0) / 1_000
    }

    private var currentSeconds: TimeInterval {
        player.duration > 0 ? player.progress * player.duration : 0
    }

    private func load() async {
        loadState = .loading
        let data: Data?
        switch source {
        case let .data(bytes):
            data = bytes
        case let .mediaAsset(id):
            data = await fetch(id)
        }

        // The view left or the source changed while downloading. The next load owns the state.
        guard !Task.isCancelled else { return }

        if let data, player.load(data: data) {
            loadState = .loaded
        } else {
            loadState = .failed
        }
    }
}

/// Records a voice answer: tap to start, tap to stop (auto-stops at the cap). Once a
/// take exists the parent swaps in the playback preview, so this view only owns the
/// idle and recording states. Leaving the screen mid-take stops the microphone and
/// hands over what was said so far.
struct DailyVoiceRecorderView: View {
    let onRecorded: (URL, Int) -> Void

    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var buttonSize: CGFloat = 84
    @State private var recorder = DailyVoiceRecorder()
    /// The last take handed to `onRecorded`, so the phase change and the disappear
    /// path can never deliver the same take twice.
    @State private var deliveredURL: URL?

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            recordButton

            caption

            if recorder.isTakeTooShort {
                message(.dailyChallengeVoiceTooShort)
            }

            if recorder.permissionDenied {
                message(.dailyChallengeVoicePermissionDenied)

                Button(action: openSettings) {
                    Text(.commonOpenSettings)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PaeoniaSpacing.space8)
        .onChange(of: recorder.phase) { _, phase in
            if phase == .recorded {
                deliverTake()
            }
        }
        .onChange(of: recorder.isTakeTooShort) { _, isTooShort in
            // The take vanished, so tell VoiceOver users why.
            if isTooShort {
                AccessibilityNotification.Announcement(String(localized: .dailyChallengeVoiceTooShort)).post()
            }
        }
        .onDisappear {
            // `onChange` no longer fires once the view is gone, so hand the take over here.
            recorder.finishForDisappear()
            deliverTake()
        }
    }

    private var isRecording: Bool {
        recorder.phase == .recording
    }

    private var recordingClock: String {
        "\(voiceClock(recorder.elapsed)) / \(voiceClock(recorder.maxDuration))"
    }

    private var tint: Color {
        isRecording ? .paeoniaError : .paeoniaAccentPrimary
    }

    /// A large round button: tap to start, tap again to stop. It breathes while the
    /// microphone is on.
    private var recordButton: some View {
        Button(action: toggle) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: min(buttonSize, 120)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.paeoniaTextInverse, tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.breathe, isActive: isRecording)
                .shadow(color: tint.opacity(0.45), radius: 20)
        }
        .buttonStyle(.plain)
        .disabled(recorder.phase == .starting)
        .accessibilityLabel(Text(isRecording ? .dailyChallengeVoiceStopRecording : .dailyChallengeVoiceRecord))
        .accessibilityValue(isRecording ? voiceClock(recorder.elapsed) : "")
    }

    /// "Tap to record", or the running clock while recording. The button already
    /// speaks both, so VoiceOver skips this line.
    private var caption: some View {
        Group {
            if isRecording {
                HStack(spacing: PaeoniaSpacing.space8) {
                    RecordingDot()
                    Text(recordingClock)
                        .monospacedDigit()
                        .foregroundStyle(.paeoniaTextPrimary)
                }
            } else {
                Text(.dailyChallengeVoiceRecord)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .font(PaeoniaTypography.body)
        .accessibilityHidden(true)
    }

    private func message(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggle() {
        switch recorder.phase {
        case .recording:
            recorder.stopRecording()
        case .idle, .recorded:
            Task { await recorder.startRecording() }
        case .starting:
            break
        }
    }

    private func deliverTake() {
        guard
            recorder.phase == .recorded,
            let url = recorder.recordedURL,
            let durationMs = recorder.recordedDurationMs,
            deliveredURL != url
        else { return }
        deliveredURL = url
        onRecorded(url, durationMs)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// A small red dot that pulses while the microphone is on. It stays still under
/// Reduce Motion.
private struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 8
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(.paeoniaError)
            .frame(width: size, height: size)
            .opacity(isDimmed ? 0.3 : 1)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(PaeoniaMotion.standardCurve(duration: 0.8).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

/// Formats seconds as minutes and seconds, such as "0:12".
private func voiceClock(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
}
