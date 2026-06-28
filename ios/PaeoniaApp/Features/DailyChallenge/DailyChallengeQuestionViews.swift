import SwiftUI

struct DailyQuestionStatusView: View {
    let question: DailyChallengeQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            ForEach(statusLines) { line in
                DailyStatusLine(
                    systemImage: line.systemImage,
                    title: line.title,
                    date: line.date,
                    tint: line.tint
                )
            }
        }
    }

    /// Both people's status for this question, ordered chronologically: answered
    /// events (which carry a timestamp) come first, oldest to newest, and a still
    /// "you haven't answered yet" line sits last as the unresolved present. In the
    /// common case that puts "your partner answered" above "you haven't answered yet".
    private var statusLines: [DailyStatusLineModel] {
        var lines: [DailyStatusLineModel] = []

        if let partnerAnswer = question.partnerAnswer {
            // Same wording whether revealed or not — the timestamp shows when the
            // partner answered, not when it became visible to you. Only the icon
            // distinguishes a revealed answer (heart) from a still-hidden one (lock).
            lines.append(
                DailyStatusLineModel(
                    id: "partner",
                    systemImage: question.canViewPartnerAnswer ? "heart.circle.fill" : "lock.circle.fill",
                    title: .dailyChallengePartnerHidden,
                    date: partnerAnswer.answeredAt,
                    tint: question.canViewPartnerAnswer ? .paeoniaAccentPrimary : .paeoniaTextTertiary
                )
            )
        }

        if let ownAnswer = question.ownAnswer {
            lines.append(
                DailyStatusLineModel(
                    id: "own",
                    systemImage: "checkmark.circle.fill",
                    title: .dailyChallengeYouAnswered,
                    date: ownAnswer.answeredAt,
                    tint: .paeoniaSuccess
                )
            )
        } else {
            lines.append(
                DailyStatusLineModel(
                    id: "own",
                    systemImage: "circle",
                    title: .dailyChallengeNotAnswered,
                    date: nil,
                    tint: .paeoniaTextTertiary
                )
            )
        }

        return lines.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return false
            }
        }
    }
}

private struct DailyStatusLineModel: Identifiable {
    let id: String
    let systemImage: String
    let title: LocalizedStringResource
    let date: Date?
    let tint: Color
}

private struct DailyStatusLine: View {
    let systemImage: String
    let title: LocalizedStringResource
    let date: Date?
    let tint: Color

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(title)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)

            if let date {
                Text(date, format: .dateTime.hour().minute())
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
    }
}

struct DailyAnswerDetailsView: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let detail = question.ownAnswerDetail {
                DailyVisibleAnswerBlock(
                    title: .dailyChallengeYourAnswerTitle,
                    detail: detail,
                    participants: participants,
                    mediaKind: question.mediaAnswerKind
                )
            }

            if let detail = question.partnerAnswerDetail, detail.canViewAnswer {
                DailyVisibleAnswerBlock(
                    title: .dailyChallengePartnerAnswerTitle,
                    detail: detail,
                    participants: participants,
                    mediaKind: question.mediaAnswerKind
                )
            } else if question.partnerAnswer != nil, !question.canViewPartnerAnswer {
                Text(.dailyChallengePartnerHiddenMessage)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DailyVisibleAnswerBlock: View {
    let title: LocalizedStringResource
    let detail: DailyQuestionAnswerDetail
    var participants = DailyChallengeParticipants()
    var mediaKind: DailyChallengeAnswerKind = .photo

    var body: some View {
        // A combined answer can carry several parts at once, so each present part is
        // shown — media first, then a partner pick, then the text caption beneath.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            if let mediaAssetID = detail.mediaAssetIDs.first {
                if mediaKind == .voice {
                    DailyVoicePlaybackView(source: .mediaAsset(mediaAssetID))
                } else {
                    DailyAnswerImageView(mediaAssetID: mediaAssetID)
                }
            }

            if let selectedUserID = detail.selectedUserID {
                // A partner-choice answer reveals as the chosen person's name.
                Text(participants.name(for: selectedUserID))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
            }

            if let textBody = detail.textBody, !textBody.isEmpty {
                Text(textBody)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
    }
}

/// The text entry field used inside the answering flow. The Send action lives in
/// the flow's fixed bottom bar (so it stays above the keyboard), so this view is
/// just the labelled, bordered field with a placeholder and focus ring.
///
/// It starts compact and grows line by line with what's typed, up to a cap, after
/// which it scrolls. It never greedily fills the screen, so the answering flow can
/// keep the whole question-and-field cluster low, within thumb reach.
struct DailyAnswerTextField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.dailyChallengeTextAnswerLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            TextField(
                text: $text,
                prompt: Text(.dailyChallengeTextAnswerPlaceholder),
                axis: .vertical
            ) {
                Text(.dailyChallengeTextAnswerLabel)
            }
            .lineLimit(3...8)
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(PaeoniaSpacing.space12)
            .focused(isFocused)
            .background(.paeoniaBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                    .stroke(
                        isFocused.wrappedValue ? Color.paeoniaAccentPrimary : Color.paeoniaSurfacePressed,
                        lineWidth: isFocused.wrappedValue ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                    )
            }
            .animation(PaeoniaMotion.stateChange, value: isFocused.wrappedValue)
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

    private let avatarSize: CGFloat = 104

    var body: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space24) {
            ForEach(options) { option in
                avatarOption(option)
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
                ZStack(alignment: .topTrailing) {
                    PaeoniaProfilePhotoAvatar(
                        mediaAssetID: option.profilePhotoAssetID,
                        name: option.avatarName,
                        tint: .paeoniaAccentPrimary,
                        size: avatarSize
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.paeoniaSuccess : Color.clear,
                                lineWidth: 3
                            )
                    }

                    if isSelected {
                        selectedBadge
                    }
                }

                Text(option.label)
                    .font(isSelected ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
                    .foregroundStyle(isSelected ? Color.paeoniaTextPrimary : Color.paeoniaTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.stateChange, value: isSelected)
        .accessibilityLabel(Text(option.label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A green disc with a checkmark, rimmed in the background colour so it reads as
    /// a badge sitting on the selected avatar's top-right edge.
    private var selectedBadge: some View {
        Circle()
            .fill(Color.paeoniaSuccess)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.paeoniaTextInverse)
            }
            .overlay {
                Circle().strokeBorder(Color.paeoniaBackgroundPrimary, lineWidth: 2)
            }
            .offset(x: 4, y: -4)
            .accessibilityHidden(true)
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
