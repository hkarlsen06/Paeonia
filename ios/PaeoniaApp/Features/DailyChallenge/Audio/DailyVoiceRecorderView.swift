import Foundation
import SwiftUI
import UIKit

/// Records a voice answer: tap to start, tap to stop (auto-stops at the cap). Once a
/// take exists the parent swaps in the playback preview, so this view only owns the
/// idle and recording states. Leaving the screen mid-take stops the microphone and
/// hands over what was said so far.
struct DailyVoiceRecorderView: View {
    let onRecorded: (URL, Int) -> Void
    var isCompact = false
    var onRecordingChange: (Bool) -> Void = { _ in }

    @Environment(\.dailyAnswerComposerColors) private var colors

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var buttonSize: CGFloat = 84
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var recorder = DailyVoiceRecorder()
    /// The last take handed to `onRecorded`, so the phase change and the disappear
    /// path can never deliver the same take twice.
    @State private var deliveredURL: URL?

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if isCompact {
                HStack(spacing: PaeoniaSpacing.space12) {
                    recordButton
                    caption
                    Spacer(minLength: 0)
                }
            } else {
                recordButton
                caption
            }

            if recorder.isTakeTooShort {
                message(.dailyChallengeVoiceTooShort)
            }

            if recorder.permissionDenied {
                message(.dailyChallengeVoicePermissionDenied)

                Button(action: openSettings) {
                    Text(.commonOpenSettings)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PaeoniaSpacing.space8)
        .onChange(of: recorder.phase) { _, phase in
            onRecordingChange(phase == .starting || phase == .recording)
            if phase == .recorded {
                deliverTake()
            }
        }
        .onChange(of: recorder.hasStartFailed) { _, failed in
            if failed {
                bannerCenter.show(.error(message: String(localized: .dailyVoiceErrorStartFailed)))
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
            onRecordingChange(false)
        }
    }

    private var isRecording: Bool {
        recorder.phase == .recording
    }

    private var recordingClock: String {
        "\(voiceClock(recorder.elapsed)) / \(voiceClock(recorder.maxDuration))"
    }

    private var tint: Color {
        isRecording ? .paeoniaError : colors.accent
    }

    /// A large round button: tap to start, tap again to stop. It breathes while the
    /// microphone is on.
    private var recordButton: some View {
        Button(action: toggle) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: isCompact ? 44 : min(buttonSize, 120)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors.control, tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.breathe, isActive: isRecording && !reduceMotion)
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
                        .foregroundStyle(colors.foreground)
                }
            } else {
                Text(.dailyChallengeVoiceRecord)
                    .foregroundStyle(colors.secondary)
            }
        }
        .font(PaeoniaTypography.body)
        .accessibilityHidden(true)
    }

    private func message(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(colors.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggle() {
        onRecordingChange(!isRecording)
        switch recorder.phase {
        case .recording:
            recorder.stopRecording()
        case .idle, .recorded:
            Task {
                await recorder.startRecording()
                onRecordingChange(recorder.phase == .starting || recorder.phase == .recording)
            }
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
