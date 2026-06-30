import SwiftUI

struct DailyQuestionStatusView: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()

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

    /// Both people's status for this question, with the partner always on top: their
    /// line first (when they've answered), then yours. Putting the partner first means
    /// once you reply you read their status before your own, rather than by whoever
    /// happened to answer first.
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
                    title: .dailyChallengePartnerHidden(participants.partnerName),
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

        return lines
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
                // Both people's timestamps read the same relative way ("2 h ago"), so
                // the line never mixes a clock time with a relative one.
                Text(date, format: relativeDateFormat)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
    }

    private var relativeDateFormat: Date.RelativeFormatStyle {
        var format = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .abbreviated)
        format.capitalizationContext = .beginningOfSentence
        return format
    }
}

struct DailyAnswerDetailsView: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let detail = consolidatedChoiceDetail {
                // Both people picked the same person and added nothing else, so the two
                // answer rows would read identically. Collapse them into one block
                // headed by both names rather than repeating the same pick twice.
                DailyVisibleAnswerBlock(
                    title: bothAnswererTitle,
                    detail: detail,
                    participants: participants,
                    mediaKind: question.mediaAnswerKind
                )
            } else {
                // Partner always on top, then you — so once you reply you read their
                // answer first, not what you just wrote.
                ForEach(orderedAnswerBlocks) { block in
                    DailyVisibleAnswerBlock(
                        title: block.title,
                        detail: block.detail,
                        participants: participants,
                        mediaKind: question.mediaAnswerKind
                    )
                }

                if shouldShowPartnerHidden {
                    Text(.dailyChallengePartnerHiddenMessage(participants.partnerName))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One revealed answer paired with the name heading it. Identified by the answer
    /// id so the ordered list stays stable across reloads.
    private struct AnswerBlock: Identifiable {
        let id: UUID
        let title: String
        let detail: DailyQuestionAnswerDetail
    }

    /// The visible answers with the partner always on top, then you. The partner's
    /// answer shows only once it's viewable; your answer is headed "You" (never your
    /// own name).
    private var orderedAnswerBlocks: [AnswerBlock] {
        var blocks: [AnswerBlock] = []

        if let detail = question.partnerAnswerDetail, detail.canViewAnswer {
            blocks.append(AnswerBlock(id: detail.answerID, title: participants.partnerName, detail: detail))
        }

        if let detail = question.ownAnswerDetail {
            blocks.append(AnswerBlock(id: detail.answerID, title: youTitle, detail: detail))
        }

        return blocks
    }

    /// Shown when the partner has answered but their reply is still hidden behind your
    /// own answer — so there's no revealed partner block to render in its place. Never
    /// shown alongside a revealed partner block (that block always wins).
    private var shouldShowPartnerHidden: Bool {
        question.partnerAnswer != nil
            && !question.canViewPartnerAnswer
            && !(question.partnerAnswerDetail?.canViewAnswer ?? false)
    }

    /// The own answer to render when both partners share one partner-choice pick — the
    /// two answers are identical here, so either stands in for the single shared block.
    private var consolidatedChoiceDetail: DailyQuestionAnswerDetail? {
        guard question.sharedPartnerChoiceUserID != nil else { return nil }
        return question.ownAnswerDetail
    }

    /// The current user's heading — always "You", never their name.
    private var youTitle: String {
        String(localized: .dailyChallengeChoiceYou)
    }

    /// Both answerers' names for a shared answer's heading, partner first, e.g. "Oda &
    /// You". The current user always reads as "You" rather than their name.
    private var bothAnswererTitle: String {
        "\(participants.partnerName) & \(youTitle)"
    }
}

private struct DailyVisibleAnswerBlock: View {
    /// The person's name heading this answer (their nickname, or a "You"/"Partner"
    /// fallback) — data, so it renders verbatim rather than as a localization key.
    let title: String
    let detail: DailyQuestionAnswerDetail
    var participants = DailyChallengeParticipants()
    var mediaKind: DailyChallengeAnswerKind = .photo

    var body: some View {
        // A combined answer can carry several parts at once, so each present part is
        // shown — media first, then a partner pick, then the text caption beneath.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(verbatim: title)
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
                // A partner-choice answer reveals as the chosen person's avatar and
                // name — the same avatar shown while answering.
                DailyChosenPersonView(
                    option: participants.option(for: selectedUserID),
                    fallbackName: participants.name(for: selectedUserID)
                )
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

/// A revealed partner-choice answer: the chosen person's avatar beside their name,
/// using the same avatar component as the picker shown while answering.
private struct DailyChosenPersonView: View {
    let option: DailyChallengeParticipants.Option?
    let fallbackName: String

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: option?.profilePhotoAssetID,
                name: option?.avatarName ?? fallbackName,
                tint: .paeoniaAccentPrimary,
                size: 44
            )

            Text(option?.label ?? fallbackName)
                .font(PaeoniaTypography.body.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
        }
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

    /// Mirrors the focus ring's color/width so they can be driven by an explicit
    /// `withAnimation` mutation instead of an `.animation(_:value:)` modifier. The
    /// ring is drawn in an `.overlay`, so its *frame* always matches the field's —
    /// which keeps moving as the keyboard rises, via SwiftUI's automatic keyboard
    /// avoidance. Any `.animation(_:value:)` modifier on that overlay, even scoped to
    /// just the stroke shape, still re-times that frame's keyboard-driven movement
    /// onto its own fixed curve, fighting the keyboard's real timing and bouncing —
    /// scoping it to "just the shape" doesn't help, because the shape's frame is the
    /// thing bouncing. Driving these two plain values from `withAnimation` instead
    /// touches nothing but the values themselves, so the keyboard-driven frame is
    /// never part of the animated transaction.
    @State private var strokeColor = Color.paeoniaSurfacePressed
    @State private var strokeWidth = PaeoniaRadius.strokeDefault

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
                    .stroke(strokeColor, lineWidth: strokeWidth)
            }
        }
        .onAppear { syncStroke(focused: isFocused.wrappedValue, animated: false) }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            syncStroke(focused: focused, animated: true)
        }
    }

    private func syncStroke(focused: Bool, animated: Bool) {
        let apply = {
            strokeColor = focused ? .paeoniaAccentPrimary : .paeoniaSurfacePressed
            strokeWidth = focused ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
        }
        if animated {
            withAnimation(PaeoniaMotion.stateChange, apply)
        } else {
            apply()
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
