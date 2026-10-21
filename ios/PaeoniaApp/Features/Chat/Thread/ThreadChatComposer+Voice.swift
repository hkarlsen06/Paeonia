import SwiftUI

extension ThreadChatComposer {
    // MARK: - Voice

    var recordingBar: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            roundButton(
                systemImage: "trash",
                label: .dailyChatComposerDeleteRecording,
                isProminent: false,
                tint: .paeoniaError,
                action: discardRecording
            )

            HStack(spacing: PaeoniaSpacing.space8) {
                RecordingDot()
                Text(verbatim: "\(voiceClock(recorder.elapsed)) / \(voiceClock(recorder.maxDuration))")
                    .font(PaeoniaTypography.body.monospacedDigit())
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(.dailyChatComposerRecording))
            .accessibilityValue(voiceClock(recorder.elapsed))

            roundButton(
                systemImage: "arrow.up",
                label: .dailyChatComposerSendRecording,
                isProminent: true,
                isBusy: recorder.phase == .starting || sendsWhenStopped,
                action: stopAndSend
            )
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
        .frame(minHeight: Self.controlHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    var reviewBar: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            roundButton(
                systemImage: "trash",
                label: .dailyChatComposerDeleteRecording,
                isProminent: false,
                tint: .paeoniaError,
                action: discardRecording
            )
            if let url = recorder.recordedURL, let data = try? Data(contentsOf: url) {
                DailyVoicePlaybackView(source: .data(data), fallbackDurationMs: recorder.recordedDurationMs)
            }
            roundButton(
                systemImage: "arrow.up",
                label: .dailyChatComposerSendRecording,
                isProminent: true,
                isBusy: isSubmitting,
                action: { Task { await sendRecording() } }
            )
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(minHeight: Self.controlHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    func startRecording() {
        isFocused = false
        sendsWhenStopped = false
        Task { await recorder.startRecording() }
    }

    private func stopAndSend() {
        switch recorder.phase {
        case .recording:
            sendsWhenStopped = true
            recorder.stopRecording()
        case .starting:
            // Nothing is recorded yet, so there is nothing to send.
            recorder.reset()
        case .idle, .recorded:
            break
        }
    }

    private func discardRecording() {
        sendsWhenStopped = false
        recorder.reset()
    }

    func sendRecording() async {
        guard !isSubmitting, let url = recorder.recordedURL, let durationMs = recorder.recordedDurationMs else {
            return
        }
        isSubmitting = true
        _ = await onSendVoice(url, durationMs)
        // The message keeps its own copy of the recording, so the file can go.
        recorder.reset()
        isSubmitting = false
    }
}
