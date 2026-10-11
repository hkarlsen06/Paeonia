import PhotosUI
import SwiftUI

/// The chat's own composer, in place of ExyteChat's. The field, the reply banner, and
/// the photo drawer follow Tidex's chat. With an empty field the round button records
/// a voice message instead of sending, using the same recorder as voice answers.
///
/// Recording: tap the microphone to start, the arrow to stop and send, or the bin to
/// throw it away. A take that hits the one-minute limit stops by itself and waits,
/// so it can be played back before sending.
struct DailyChatComposer: View {
    /// ExyteChat's text, so its keyboard handling keeps working.
    let text: Binding<String>
    let replyPreview: DailyChatReplyPreview?
    /// Changes when the field should take focus.
    let focusRequest: Int
    let onCancelReply: () -> Void
    let onSendText: (String) async -> Bool
    let onSendPhotos: (String, [DailyQuestionChatPhoto]) async -> Bool
    let onSendVoice: (URL, Int) async -> Bool
    let onTextChanged: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @FocusState private var isFocused: Bool
    @State private var recorder = DailyVoiceRecorder()
    @State private var staging = DailyChatPhotoStaging()
    @State private var isSubmitting = false
    /// True when the person tapped send while recording, so the take sends once it stops.
    @State private var sendsWhenStopped = false

    private static let controlHeight: CGFloat = 52
    private static let cornerRadius: CGFloat = 24
    private static let buttonDiameter: CGFloat = 36

    var body: some View {
        // Rows above the field sit outside the scroll view. A row appearing inside it
        // would shift the field for a frame before it settles.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let replyPreview {
                replyBanner(replyPreview)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
            if let notice {
                Text(notice)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PaeoniaSpacing.space8)
            }
            if recorder.permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(.commonOpenSettings)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
            }
            if !staging.staged.isEmpty || staging.isProcessing {
                DailyChatStagedPhotosRow(staging: staging)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
            fieldScrollView
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.top, PaeoniaSpacing.space4)
        .padding(.bottom, PaeoniaSpacing.space8)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: replyPreview)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: mode)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: staging.staged)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: staging.isDrawerOpen)
        // Size every row to its content. ExyteChat offers the input the full screen height.
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: focusRequest) { isFocused = true }
        .onChange(of: text.wrappedValue) { _, newText in onTextChanged(newText) }
        // Typing closes the drawer. Opening the drawer puts the keyboard away.
        .onChange(of: isFocused) { _, focused in if focused { staging.isDrawerOpen = false } }
        .onChange(of: staging.isDrawerOpen) { _, isOpen in if isOpen { isFocused = false } }
        .photosPicker(
            isPresented: $staging.isShowingLibrary,
            selection: $staging.pickerItems,
            maxSelectionCount: staging.librarySelectionLimit,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $staging.isShowingCamera) {
            DailyCameraPicker(onCapture: staging.addCameraPhoto)
                .ignoresSafeArea()
        }
        .onChange(of: recorder.phase) { _, phase in
            guard phase == .recorded, sendsWhenStopped else { return }
            sendsWhenStopped = false
            Task { await sendRecording() }
        }
        .onChange(of: recorder.isTakeTooShort) { _, isTooShort in
            if isTooShort {
                sendsWhenStopped = false
                AccessibilityNotification.Announcement(String(localized: .dailyChallengeVoiceTooShort)).post()
            }
        }
        // A half-made recording never sends from a screen that is gone.
        .onDisappear { recorder.reset() }
    }

    private enum Mode: Equatable {
        case text
        case recording
        case review
    }

    private var mode: Mode {
        switch recorder.phase {
        case .idle: .text
        case .starting, .recording: .recording
        case .recorded: sendsWhenStopped ? .recording : .review
        }
    }

    private var notice: LocalizedStringResource? {
        if recorder.permissionDenied { return .dailyChatComposerPermissionDenied }
        if recorder.isTakeTooShort { return .dailyChallengeVoiceTooShort }
        return nil
    }

    /// A drag down on the composer dismisses the keyboard the same way a drag on the
    /// list does. The scroll itself is cancelled, so only the keyboard follows the finger.
    private var fieldScrollView: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space8) {
                field
                if staging.isDrawerOpen, mode == .text {
                    DailyChatAttachmentDrawer(staging: staging)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
                .fixedSize(horizontal: false, vertical: true)
                .visualEffect { content, proxy in
                    content.offset(y: -proxy.frame(in: .scrollView).minY)
                }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var field: some View {
        switch mode {
        case .text: textField
        case .recording: recordingBar
        case .review: reviewBar
        }
    }

    // MARK: - Text

    private var trimmedText: String {
        text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Something to send: text, picked photos, or both.
    private var canSend: Bool {
        (!trimmedText.isEmpty || !staging.staged.isEmpty) && !staging.isProcessing
    }

    private var textField: some View {
        HStack(alignment: .bottom, spacing: PaeoniaSpacing.space8) {
            roundButton(
                systemImage: staging.isDrawerOpen ? "xmark" : "plus",
                label: .dailyChatComposerAddPhoto,
                isProminent: false,
                tint: .paeoniaTextPrimary,
                action: { staging.isDrawerOpen.toggle() }
            )
            .glassEffect(.regular, in: Circle())
            .padding(.bottom, 4)
            composerCapsule
        }
    }

    private var composerCapsule: some View {
        HStack(alignment: .bottom, spacing: PaeoniaSpacing.space8) {
            TextField(
                text: text,
                prompt: Text(.dailyChatComposerPlaceholder),
                axis: .vertical
            ) {
                Text(.dailyChatComposerPlaceholder)
            }
            .textFieldStyle(.plain)
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(1...7)
            .focused($isFocused)
            .disabled(staging.isProcessing)
            .padding(.vertical, PaeoniaSpacing.space12 + 2)
            .frame(minHeight: Self.controlHeight)

            trailingButton
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: trimmedText.isEmpty)
        .padding(.leading, PaeoniaSpacing.space16)
        .padding(.trailing, PaeoniaSpacing.space4)
        .frame(minHeight: Self.controlHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.paeoniaAccentPrimary.opacity(isFocused ? 0.7 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        // The whole capsule focuses the field, not just the text. VoiceOver focuses the field directly.
        .onTapGesture { isFocused = true }
        .accessibilityAddTraits(.isButton)
    }

    /// The mic while the field is empty, the send button otherwise. A full-height slot
    /// centers it on one line and keeps it at the bottom when the text grows.
    private var trailingButton: some View {
        Group {
            if trimmedText.isEmpty, staging.staged.isEmpty, !staging.isProcessing {
                roundButton(
                    systemImage: "mic.fill",
                    label: .dailyChatComposerRecord,
                    isProminent: false,
                    action: startRecording
                )
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                roundButton(
                    systemImage: "arrow.up",
                    label: .dailyChatComposerSend,
                    isProminent: true,
                    isBusy: isSubmitting || staging.isProcessing,
                    action: sendText
                )
                .disabled(!canSend)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: Self.controlHeight)
    }

    private func sendText() {
        let body = trimmedText
        let photos = staging.photos
        guard canSend, !isSubmitting else { return }
        isSubmitting = true
        Task {
            let sent = photos.isEmpty ? await onSendText(body) : await onSendPhotos(body, photos)
            if sent {
                text.wrappedValue = ""
                staging.clear()
            }
            isSubmitting = false
        }
    }

    // MARK: - Pieces

    private func roundButton(
        systemImage: String,
        label: LocalizedStringResource,
        isProminent: Bool,
        tint: Color = .paeoniaAccentPrimary,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().tint(.paeoniaTextInverse)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isProminent ? Color.paeoniaTextInverse : tint)
                }
            }
            .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
            .background(isProminent ? tint : tint.opacity(0.16), in: Circle())
            // The circle stays 36pt. The tap area is 44pt.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(Text(label))
    }
}

extension DailyChatComposer {
    private func replyBanner(_ preview: DailyChatReplyPreview) -> some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.paeoniaAccentPrimary)
                .frame(width: 3)
            DailyChatReplyPreviewContent(preview: preview, snippetLineLimit: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .padding(.trailing, PaeoniaSpacing.space32)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onCancelReply) {
                Image(systemName: "xmark")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.paeoniaTextPrimary.opacity(0.08), in: Circle())
                    // The circle stays small. The tap area is at least 44pt.
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.dailyChatReplyCancel))
            .padding(PaeoniaSpacing.space8)
        }
    }

    // MARK: - Voice

    private var recordingBar: some View {
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

    private var reviewBar: some View {
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

    private func startRecording() {
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

    private func sendRecording() async {
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
