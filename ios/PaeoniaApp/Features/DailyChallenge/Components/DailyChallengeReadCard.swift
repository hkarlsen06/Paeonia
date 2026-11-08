import SwiftUI

/// A "saved, sending" answer to keep visible in a read overview while it finishes
/// sending: a photo/voice note plays from its staged bytes, a partner pick and/or text
/// caption show what was chosen or written. Any combination can be present.
nonisolated struct DailySendingPreview: Equatable, Hashable, Sendable {
    var mediaKind: DailyChallengeAnswerKind = .photo
    var mediaData: Data?
    var voiceDurationMs: Int?
    var partnerChoiceName: String?
    var text: String?
    var mediaAccessibilityText: String?
    var isHeldOnPhone = false
}

/// A short row for one question in a list: the question, who has answered, and what
/// happens next. The answers themselves live on the question's own page, so tapping
/// a row you have answered opens that page, where the answers start the chat.
///
/// A question the partner answered that the user can still answer opens the answer flow
/// instead, and is the zoom source for it. A row whose answer is still saving shows what
/// was saved.
struct DailyChallengeReadCard: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()
    var sending: DailySendingPreview?
    var zoomNamespace: Namespace.ID?
    var isHighlighted = false
    var onAnswer: () -> Void = {}
    var lastMessagePreview: String?
    var activityDate: Date?
    var hasUnreadChat = false
    /// The user can read the partner's answer and hasn't seen it yet.
    var hasNewPartnerAnswer = false
    /// Opens the question's page. Only a question the user has answered has one.
    var onOpen: (() -> Void)?
    /// The topic's name, for a topic question listed with the daily ones.
    var topicTitle: String?
    /// Today's completed question stays at the top, with earlier unanswered questions below it.
    var completionState: DailyChallengeCardState?
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A question the partner answered that the user can still answer to reveal the
    /// reply. When sending, the row shows the "saved, sending" preview instead, so this
    /// stays false.
    private var isAnswerable: Bool {
        sending == nil && question.isAwaitingCurrentUserAnswer
    }

    private var opensPage: Bool {
        (question.hasOwnAnswer || isUnread || sending != nil) && onOpen != nil
    }

    private var isUnread: Bool {
        hasUnreadChat && question.isChatAvailable
    }

    /// Something from the partner to look at: a chat message or their answer.
    private var isNew: Bool {
        isUnread || (hasNewPartnerAnswer && question.isChatAvailable)
    }

    var body: some View {
        PaeoniaCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                cardAction
                if let completionState, !completionState.lockedPartnerQuestions.isEmpty {
                    LockedPartnerQuestionRows(
                        state: completionState,
                        partnerName: participants.partnerName,
                        partnerPhotoAssetID: participants.partnerProfilePhotoAssetID,
                        onOpen: onOpenPartnerQuestion
                    )
                    .padding(.horizontal, PaeoniaSpacing.cardContentPadding)
                    .padding(.bottom, PaeoniaSpacing.cardContentPadding)
                }
            }
        }
        .zoomSource(question.id, in: isAnswerable ? zoomNamespace : nil)
        .overlay {
            let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
            if isHighlighted {
                shape.stroke(.paeoniaAccentPrimary, lineWidth: 2)
            } else if isNew {
                shape.strokeBorder(.paeoniaAccentPrimary, lineWidth: PaeoniaRadius.strokeEmphasis)
            }
        }
    }

    private var cardAction: some View {
        Group {
            if isAnswerable {
                Button(action: onAnswer) { card }
                    .buttonStyle(.plain)
            } else if opensPage, let onOpen {
                Button(action: onOpen) { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        .accessibilityIdentifier(
            completionState != nil || (question.isCurrentDay && (question.hasOwnAnswer || sending != nil))
                ? "daily.done.openConversation" : "daily.question.\(question.id.uuidString)"
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if completionState != nil {
                completionLabel
            }
            questionHeading

            if let sending, completionState == nil {
                DailySendingAnswerView(
                    mediaKind: sending.mediaKind,
                    mediaData: sending.mediaData,
                    voiceDurationMs: sending.voiceDurationMs,
                    partnerChoiceName: sending.partnerChoiceName,
                    text: sending.text,
                    mediaAccessibilityText: sending.mediaAccessibilityText
                )
            } else {
                if let preview = lastMessagePreview?.trimmedNonEmpty, !isAnswerable {
                    Text(verbatim: preview)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                statusRow
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var questionHeading: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let topicTitle {
                Text(verbatim: topicTitle)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            if let activityDate {
                Text(activityDate, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            Text(question.prompt)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completionLabel: some View {
        Label {
            Text(.dailyChallengeHomeCompleteTitle)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaAccentPrimary)
    }

    private var statusRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
        return layout {
            HStack {
                DailyAnswerersView(question: question, participants: participants, hasPendingOwnAnswer: sending != nil)
                if dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: PaeoniaSpacing.space12)
                    accessory
                }
            }

            statusText
                .font(isNew ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.caption)
                .foregroundStyle(isNew ? Color.paeoniaTextPrimary : Color.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                accessory
            }
        }
    }

    /// What the row says about the question, in the order the cases can happen.
    private var statusText: Text {
        if isAnswerable {
            return Text(.dailyChallengePartnerHiddenMessage(participants.partnerName))
        }
        if isUnread { return Text(.dailyChatCardUnreadTitle(participants.partnerName)) }
        if sending != nil {
            return Text(question.hasPartnerAnswer
                ? .dailyChallengePartnerHidden(participants.partnerName)
                : .dailyChallengeRowWaiting(participants.partnerName))
        }
        guard question.hasOwnAnswer else { return Text(.dailyChallengeNotAnswered) }
        guard question.hasPartnerAnswer else { return Text(.dailyChallengeRowWaiting(participants.partnerName)) }
        guard question.hasRevealedPartnerAnswer else {
            return Text(.dailyChallengePartnerHidden(participants.partnerName))
        }
        if isNew { return Text(.dailyChallengeRowNewPartnerAnswer(participants.partnerName)) }
        return Text(.dailyChallengeRowBothAnswered)
    }

    @ViewBuilder
    private var accessory: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            if isNew {
                Circle()
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: 10, height: 10)
            }
            if isAnswerable || opensPage {
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Both people's avatars side by side. Whoever has answered gets a check and full
/// color; whoever hasn't is faded.
private struct DailyAnswerersView: View {
    let question: DailyChallengeQuestion
    let participants: DailyChallengeParticipants
    var hasPendingOwnAnswer = false

    private let size: CGFloat = 28

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            avatar(
                photo: participants.currentProfilePhotoAssetID,
                name: participants.currentDisplayName ?? String(localized: .dailyChallengeChoiceYou),
                tint: .paeoniaPartnerOne,
                isCurrentUser: true,
                answered: question.hasOwnAnswer || hasPendingOwnAnswer
            )
            avatar(
                photo: participants.partnerProfilePhotoAssetID,
                name: participants.partnerName,
                tint: .paeoniaPartnerTwo,
                isCurrentUser: false,
                answered: question.hasPartnerAnswer
            )
        }
        .accessibilityHidden(true)
    }

    private func avatar(photo: UUID?, name: String, tint: Color, isCurrentUser: Bool, answered: Bool) -> some View {
        PaeoniaCoupleAvatar(mediaAssetID: photo, name: name, tint: tint, size: size, isCurrentUser: isCurrentUser)
            .opacity(answered ? 1 : 0.35)
            .overlay(alignment: .bottomTrailing) {
                if answered {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.paeoniaSuccess)
                        .background(.paeoniaSurfacePrimary, in: Circle())
                        .offset(x: 2, y: 2)
                        .accessibilityHidden(true)
                }
            }
    }
}
