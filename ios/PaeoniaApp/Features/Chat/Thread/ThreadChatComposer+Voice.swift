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
                systemImage: "stop.fill",
                label: .dailyChallengeVoiceStopRecording,
                isProminent: true,
                isBusy: recorder.phase == .starting,
                action: stopRecording
            )
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
        .frame(minHeight: Self.controlHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    var reviewBar: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.mediaAccessibilityTranscript).font(PaeoniaTypography.caption)
            TextField(String(localized: .mediaAccessibilityTranscriptHint), text: $voiceTranscript, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            if DailyAnswerDraft.measuredLength(of: voiceTranscript) > 10_000 {
                Text(.mediaAccessibilityTooLong).foregroundStyle(.paeoniaErrorText)
            }
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
    }

    func startRecording() {
        isFocused = false
        Task { await recorder.startRecording() }
    }

    private func stopRecording() {
        switch recorder.phase {
        case .recording:
            recorder.stopRecording()
        case .starting:
            // Nothing is recorded yet, so there is nothing to send.
            recorder.reset()
        case .idle, .recorded:
            break
        }
    }

    private func discardRecording() {
        voiceDraftEditing?.discard()
        recorder.reset()
        voiceTranscript = ""
    }

    func sendRecording() async {
        guard !isSubmitting, let url = recorder.recordedURL, let durationMs = recorder.recordedDurationMs else {
            return
        }
        guard DailyAnswerDraft.measuredLength(of: voiceTranscript) <= 10_000 else { return }
        let sentTranscript = voiceTranscript
        isSubmitting = true
        guard await onSendVoice(url, durationMs, voiceTranscript) else {
            isSubmitting = false
            return
        }
        if recorder.recordedURL == url, voiceTranscript == sentTranscript {
            voiceDraftEditing?.discard()
            voiceTranscript = ""
            // The message keeps its own copy. Keep a take or transcript changed during the send.
            recorder.reset()
        }
        isSubmitting = false
    }

    func saveRecordingDraft() {
        guard recorder.phase == .recorded, let url = recorder.recordedURL,
              let durationMs = recorder.recordedDurationMs else { return }
        do {
            let audio = try Data(contentsOf: url)
            let draft = ThreadChatVoiceDraft(audio: audio, durationMs: durationMs, transcript: voiceTranscript)
            _ = voiceDraftEditing?.save(draft)
        } catch {
            bannerCenter.show(.error(
                title: String(localized: .chatPhotoDraftSaveFailedTitle),
                message: String(localized: .chatVoiceDraftSaveFailedMessage)
            ))
        }
    }

    func restoreRecording() {
        voiceDraftEditing = beginVoiceDraft()
        guard recorder.phase == .idle, let draft = voiceDraftEditing?.draft else { return }
        do {
            voiceTranscript = draft.transcript
            try recorder.restoreRecording(data: draft.audio, durationMs: draft.durationMs)
        } catch {
            // The durable copy remains available for a later retry.
            bannerCenter.show(.error(message: String(localized: .chatVoiceDraftRestoreFailed)))
        }
    }
}
