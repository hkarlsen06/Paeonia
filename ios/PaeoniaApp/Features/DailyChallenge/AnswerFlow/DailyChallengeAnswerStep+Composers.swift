import SwiftUI

extension DailyChallengeAnswerStep {
    var answerTextField: some View {
        let isWhyLine = question.answerKinds.contains(.eitherOr)
        return DailyAnswerTextField(
            text: draftBinding,
            isFocused: isFocused,
            label: isWhyLine ? .dailyChallengePickWhyLabel : .dailyChallengeTextAnswerLabel,
            placeholder: isWhyLine ? .dailyChallengePickWhyPlaceholder : .dailyChallengeTextAnswerPlaceholder,
            limit: question.maxAnswerTextLength,
            isEmbedded: true
        )
        .disabled(isRecording)
    }

    var combinedComposer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            switch question.combinedSecondaryKind {
            case .photo:
                photoComposer
            case .voice:
                voiceComposer
            case .partnerChoice, .eitherOr:
                if isKeyboardPresented {
                    compactChoice
                } else {
                    choiceComposer
                }
            default:
                EmptyView()
            }
            if !isRecording { answerTextField }
        }
    }

    @ViewBuilder
    var kindComposer: some View {
        switch composeKind {
        case .photo:
            photoComposer
        case .voice:
            voiceComposer
        case .partnerChoice, .eitherOr:
            choiceComposer
        case .text:
            answerTextField
        default:
            DailyUnsupportedAnswerMessage(answerKinds: question.answerKinds)
        }
    }

    private var photoComposer: some View {
        DailyPhotoAnswerComposer(
            imageData: stagedMediaData,
            isPreparing: viewModel.isPreparingPhoto(for: question.id),
            isCompact: isKeyboardPresented,
            onPick: stagePhoto,
            onPickFailed: viewModel.photoPickFailed,
            onRemove: removeStagedMedia
        )
    }

    @ViewBuilder
    private var voiceComposer: some View {
        if let voiceData = stagedMediaData {
            HStack(alignment: .center, spacing: PaeoniaSpacing.space8) {
                DailyVoicePlaybackView(
                    source: .data(voiceData),
                    fallbackDurationMs: voiceDurationMs
                )
                Button(action: removeStagedMedia) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DailyAnswerComposerColors.composer.secondary)
                .accessibilityLabel(Text(.dailyChallengeVoiceReRecord))
                .accessibilityIdentifier("daily.answer.voice.remove")
            }
        } else {
            DailyVoiceRecorderView(
                onRecorded: { url, durationMs in stageVoice(url: url, durationMs: durationMs) },
                isCompact: question.usesCombinedCompose,
                onRecordingChange: { recording in
                    if recording { isFocused.wrappedValue = false }
                    isRecording = recording
                }
            )
        }
    }

    @ViewBuilder
    private var choiceComposer: some View {
        if question.answerKinds.contains(.partnerChoice), let options = viewModel.participants.partnerChoiceOptions {
            DailyPartnerChoicePicker(options: options, selection: partnerChoiceSelection, onSelect: setPartnerChoice)
        } else if let options = question.options {
            DailyOptionChoicePicker(options: options, selection: optionChoiceSelection, onSelect: setOptionChoice)
        }
    }

    private var compactChoice: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            if let selectedPerson {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: selectedPerson.profilePhotoAssetID,
                    name: selectedPerson.avatarName,
                    tint: .paeoniaAccentPrimary,
                    size: 32
                )
                .accessibilityHidden(true)
            }
            Label {
                Text(verbatim: choiceLabel)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: hasChoice ? "checkmark.circle.fill" : "circle")
            }
            Spacer(minLength: 0)
            Button {
                isFocused.wrappedValue = false
            } label: {
                Text(.dailyChallengeComposerChange)
                    .font(PaeoniaTypography.caption)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(DailyAnswerComposerColors.composer.foreground)
        .accessibilityIdentifier("daily.answer.selectedChoice")
    }

    private var selectedPerson: DailyChallengeParticipants.Option? {
        partnerChoiceSelection.flatMap { viewModel.participants.option(for: $0) }
    }

    private var hasChoice: Bool {
        partnerChoiceSelection != nil || optionChoiceSelection != nil
    }

    private var choiceLabel: String {
        if let selectedPerson { return selectedPerson.label }
        if let optionChoiceSelection, let options = question.options {
            return options.label(for: optionChoiceSelection)
        }
        return String(localized: question.answerKinds.contains(.partnerChoice)
            ? .dailyChallengeKindChoice : .dailyChallengeKindPick)
    }
}
