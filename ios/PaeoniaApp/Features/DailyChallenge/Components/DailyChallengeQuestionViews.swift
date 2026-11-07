import SwiftUI

/// The parts of one revealed answer, without a heading or background, so both the
/// answer blocks and the chat's answer bubbles can show it.
struct DailyAnswerContent: View {
    let detail: DailyQuestionAnswerDetail
    var participants = DailyChallengeParticipants()
    var mediaKind: DailyChallengeAnswerKind = .photo

    var body: some View {
        // A combined answer can carry several parts at once, so each present part is
        // shown — media first, then a partner pick, then the text caption beneath.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if detail.canViewAnswer, let mediaAssetID = detail.mediaAssetIDs.first {
                if mediaKind == .voice {
                    DailyVoicePlaybackView(source: .mediaAsset(mediaAssetID))
                } else {
                    DailyAnswerImageView(mediaAssetID: mediaAssetID, authoredDescription: detail.mediaAccessibilityText)
                }
                DailyMediaAccessibilityText(
                    text: detail.mediaAccessibilityText, isVoice: mediaKind == .voice,
                    editingTarget: detail.isOwnAnswer && detail.answerUserID == participants.currentUserID
                        ? .daily(answerID: detail.answerID) : nil
                )
            }

            if let selectedUserID = detail.selectedUserID {
                // A partner-choice answer reveals as the chosen person's avatar and
                // name — the same avatar shown while answering.
                DailyChosenPersonView(
                    option: participants.option(for: selectedUserID),
                    fallbackName: participants.name(for: selectedUserID)
                )
            }

            if let optionLabel = detail.selectedOptionLabel {
                DailyPickedOptionView(label: optionLabel)
            }

            if let textBody = detail.textBody, !textBody.isEmpty {
                Text(textBody)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A revealed pick-one-of-two answer: the picked option, above its why line.
private struct DailyPickedOptionView: View {
    let label: String

    var body: some View {
        Label {
            Text(verbatim: label)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
    }
}

/// A revealed partner-choice answer: the chosen person's avatar beside their name,
/// using the same avatar component as the picker shown while answering.
private struct DailyChosenPersonView: View {
    let option: DailyChallengeParticipants.Option?
    let fallbackName: String

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaCoupleAvatar(
                mediaAssetID: option?.profilePhotoAssetID,
                name: option?.avatarName ?? fallbackName,
                tint: .paeoniaAccentPrimary,
                size: 44,
                isCurrentUser: option?.isCurrentUser ?? false
            )

            Text(option?.label ?? fallbackName)
                .font(PaeoniaTypography.body.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
        }
    }
}

/// The two-person picker for a partner-choice question: tap your avatar or your
/// partner's. The chosen person's photo (or initials) gets a green ring and a
/// checkmark; exactly one is selected at a time. The Send/Save action lives in the
/// flow's bottom bar like the text composer.
struct DailyPartnerChoicePicker: View {
    let options: [DailyChallengeParticipants.Option]
    let selection: UUID?
    let onSelect: (UUID) -> Void

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 64
    @Environment(\.dailyAnswerComposerColors) private var colors

    var body: some View {
        Grid(horizontalSpacing: PaeoniaSpacing.space24) {
            GridRow {
                ForEach(options) { option in
                    avatarOption(option)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func avatarOption(_ option: DailyChallengeParticipants.Option) -> some View {
        let isSelected = option.id == selection
        return Button {
            PaeoniaHaptics.selection()
            onSelect(option.id)
        } label: {
            VStack(spacing: PaeoniaSpacing.space12) {
                PaeoniaCoupleAvatar(
                    mediaAssetID: option.profilePhotoAssetID,
                    name: option.avatarName,
                    tint: .paeoniaAccentPrimary,
                    size: avatarSize, isCurrentUser: option.isCurrentUser,
                    selectionRing: isSelected ? colors.accent : .clear
                )

                HStack(spacing: PaeoniaSpacing.space8) {
                    Text(option.label)
                        .font(isSelected ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
                        .foregroundStyle(isSelected ? colors.foreground : colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(colors.accent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(PaeoniaSpacing.space8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected ? colors.selected : colors.control,
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12)
            )
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.stateChange, value: isSelected)
        .accessibilityLabel(Text(option.label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

}

struct DailyUnsupportedAnswerMessage: View {
    let answerKinds: [DailyChallengeAnswerKind]

    var body: some View {
        Text(message)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var message: LocalizedStringResource {
        if answerKinds == [.photo] {
            return .dailyChallengeNeedsPhotoMessage
        }

        if answerKinds == [.voice] {
            return .dailyChallengeNeedsVoiceMessage
        }

        return .dailyChallengeUnsupportedAnswerMessage
    }
}
