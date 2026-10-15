import SwiftUI

extension DailyChallengeAnswerStep {
    /// The composer for an answer the user already sent but can still change while
    /// it's private. Text reopens the editable field; partner choice reopens the
    /// avatar picker (pre-selected) with a line showing when it was answered.
    @ViewBuilder
    func editComposer(kind: DailyChallengeAnswerKind) -> some View {
        switch kind {
        case .partnerChoice:
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                DailyQuestionStatusView(question: question, participants: viewModel.participants)

                if let options = viewModel.participants.partnerChoiceOptions {
                    DailyPartnerChoicePicker(
                        options: options,
                        selection: partnerChoiceSelection,
                        onSelect: setPartnerChoice
                    )
                } else {
                    DailyAnswerDetailsView(question: question, participants: viewModel.participants)
                }
            }
        default:
            answerTextField
        }
    }

    /// Fades only, never slides: a slide pulls the picker up across the card and the
    /// progress bar. It fades out fast, before the field moves into its spot.
    static let foldTransition = AnyTransition.asymmetric(
        insertion: .opacity,
        removal: .opacity.animation(PaeoniaMotion.buttonPress)
    )

    /// The photo or partner pick waits to fade back in until the field, sliding down
    /// with the keyboard, has passed the spot where it sits.
    private static let secondaryFoldTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionFast)),
        removal: .opacity.animation(PaeoniaMotion.buttonPress)
    )

    /// The text field, with a tap target over it while the fold is open. A tap folds
    /// the card footer and the photo or partner pick first and only then focuses the
    /// field, so the keyboard rises into a layout that already fits. Focusing first
    /// lets the keyboard push the still-tall content up past the progress bar before
    /// anything folds. VoiceOver skips the target and focuses the field directly.
    var answerTextField: some View {
        DailyAnswerTextField(text: draftBinding, isFocused: isFocused)
            .overlay {
                if showsSecondaryComposer {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: focusAnswerField)
                        .accessibilityHidden(true)
                }
            }
    }

    private func focusAnswerField() {
        setSecondaryComposerShown(false)
        isFocused.wrappedValue = true
    }

    func setSecondaryComposerShown(_ shown: Bool) {
        guard showsSecondaryComposer != shown else { return }
        withAnimation(PaeoniaMotion.keyboard) { showsSecondaryComposer = shown }
    }

    /// For questions that accept text alongside a photo or partner pick, both
    /// composers show together, each optional, so the user can add one, the other,
    /// or both. The text field sits below so it lands just above the keyboard. While
    /// the field is focused the photo / partner pick folds away so the text composer
    /// owns the shorter height, and returns once the field is dismissed. The card is
    /// pinned to the top and the field to the bottom (see `content`), so the fold
    /// moves neither of them.
    @ViewBuilder
    var combinedComposer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            if showsSecondaryComposer {
                combinedSecondaryComposer
                    .transition(Self.secondaryFoldTransition)
            }

            answerTextField
        }
    }

    /// The non-text half of a combined question, a photo picker or partner pick. It
    /// shows above the text field and hides while the field is focused.
    @ViewBuilder
    private var combinedSecondaryComposer: some View {
        switch question.combinedSecondaryKind {
        case .photo:
            DailyPhotoAnswerComposer(
                imageData: stagedMediaData,
                isPreparing: viewModel.isPreparingPhoto(for: question.id),
                onPick: stagePhoto,
                onPickFailed: viewModel.photoPickFailed,
                onRemove: removeStagedMedia
            )
        case .partnerChoice:
            if let options = viewModel.participants.partnerChoiceOptions {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    Label {
                        Text(.dailyChallengeCombinedChoiceHint)
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)

                    DailyPartnerChoicePicker(
                        options: options,
                        selection: partnerChoiceSelection,
                        onSelect: setPartnerChoice
                    )
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    var kindComposer: some View {
        switch composeKind {
        case .partnerChoice:
            if let options = viewModel.participants.partnerChoiceOptions {
                DailyPartnerChoicePicker(
                    options: options,
                    selection: partnerChoiceSelection,
                    onSelect: setPartnerChoice
                )
            } else {
                DailyUnsupportedAnswerMessage(answerKinds: question.answerKinds)
            }
        case .photo:
            DailyPhotoAnswerComposer(
                imageData: stagedMediaData,
                isPreparing: viewModel.isPreparingPhoto(for: question.id),
                onPick: stagePhoto,
                onPickFailed: viewModel.photoPickFailed,
                onRemove: removeStagedMedia
            )
        case .voice:
            voiceComposer
        default:
            answerTextField
        }
    }

    @ViewBuilder
    private var voiceComposer: some View {
        if let voiceData = stagedMediaData {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(.dailyChallengeVoiceLabel)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)

                DailyVoicePlaybackView(
                    source: .data(voiceData),
                    fallbackDurationMs: voiceDurationMs
                )

                Button {
                    removeStagedMedia()
                } label: {
                    Label {
                        Text(.dailyChallengeVoiceReRecord)
                    } icon: {
                        Image(systemName: "arrow.counterclockwise").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity)
            }
        } else {
            DailyVoiceRecorderView(
                onRecorded: { url, durationMs in
                    stageVoice(url: url, durationMs: durationMs)
                }
            )
        }
    }
}
