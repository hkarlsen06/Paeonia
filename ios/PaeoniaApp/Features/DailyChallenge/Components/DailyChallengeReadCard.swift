import SwiftUI

/// A "saved, sending" answer to keep visible in a read overview while it finishes
/// sending: a photo/voice note plays from its staged bytes, a partner pick and/or text
/// caption show what was chosen or written. Any combination can be present.
struct DailySendingPreview {
    var mediaKind: DailyChallengeAnswerKind = .photo
    var mediaData: Data?
    var voiceDurationMs: Int?
    var partnerChoiceName: String?
    var text: String?
}

/// A read-only card showing a question and whatever is visible about it: the two
/// people's status, and any revealed answers. It is the shared building block for
/// every place a question is *shown* rather than answered — the Questions tab's
/// read sections and the Questions history flow.
///
/// The answer affordance is optional and off by default, so a card is purely
/// read-only unless a caller opts in. The Questions tab opts in for a partner
/// question the user can still answer (showing the CTA and acting as the zoom
/// source for the answer flow); the history flow never does, so a historical card
/// only ever reads back the exchange.
struct DailyChallengeReadCard: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()
    var sending: DailySendingPreview?
    var isOwnChallengeComplete = true
    var zoomNamespace: Namespace.ID?
    var isHighlighted = false
    var onAnswer: () -> Void = {}
    var onReportPartnerAnswer: ((UUID) -> Void)?
    var lastMessagePreview: String? = nil
    var hasUnreadChat = false
    var onOpenChat: (() -> Void)? = nil

    /// A partner question the user can still answer to reveal the reply. When sending,
    /// the card shows the "saved, sending" preview instead, so this stays false.
    private var isAnswerable: Bool {
        sending == nil && question.origin == .partner && question.isAvailableToAnswer
    }

    /// Whether tapping the CTA can actually open the answer flow. Answering a
    /// partner's question is gated behind finishing your own three first, so until
    /// then the CTA is shown but locked (and doesn't morph into the flow).
    private var canOpenAnswerFlow: Bool {
        isAnswerable && isOwnChallengeComplete
    }

    var body: some View {
        Group {
            if let reportablePartnerAnswerID, let onReportPartnerAnswer {
                presentedCard
                    .contextMenu {
                        Button(role: .destructive) {
                            onReportPartnerAnswer(reportablePartnerAnswerID)
                        } label: {
                            Label {
                                Text(.dailyChallengeReportPartnerAnswer)
                            } icon: {
                                Image(systemName: "exclamationmark.shield")
                            }
                        }
                    }
                    .accessibilityAction(named: Text(.dailyChallengeReportPartnerAnswer)) {
                        onReportPartnerAnswer(reportablePartnerAnswerID)
                    }
            } else {
                presentedCard
            }
        }
        // Answerable cards are the source the single-question flow zooms out of, so the
        // tapped card appears to grow into the full-screen flow. Only cards that can
        // open the flow carry it.
        .zoomSource(question.id, in: canOpenAnswerFlow ? zoomNamespace : nil)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                    .stroke(.paeoniaAccentPrimary, lineWidth: 2)
            }
        }
    }

    @ViewBuilder
    private var presentedCard: some View {
        if question.isChatAvailable, let onOpenChat {
            Button(action: onOpenChat) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                if showsChat, hasUnreadChat {
                    newMessageBadge
                }

                Text(question.prompt)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let sending {
                    // Still saving: shows whatever was saved (photo, pick, and/or
                    // caption), so the usual "not answered" status would only contradict it.
                    DailySendingAnswerView(
                        mediaKind: sending.mediaKind,
                        mediaData: sending.mediaData,
                        voiceDurationMs: sending.voiceDurationMs,
                        partnerChoiceName: sending.partnerChoiceName,
                        text: sending.text
                    )
                } else {
                    DailyQuestionStatusView(question: question, participants: participants)

                    if isAnswerable {
                        lockedPartnerAnswerHint
                        answerButton
                    } else {
                        DailyAnswerDetailsView(question: question, participants: participants)

                        if showsChat {
                            chatAffordance
                        }
                    }
                }
            }
        }
    }

    private var showsChat: Bool {
        question.isChatAvailable && onOpenChat != nil
    }

    /// Sits above the question so a tall card still shows the new message without scrolling.
    private var newMessageBadge: some View {
        Label {
            Text(.dailyChatCardNewBadge)
        } icon: {
            Image(systemName: "bubble.left.fill")
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaTextInverse)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background(.paeoniaAccentPrimary, in: Capsule())
        .accessibilityHidden(true)
    }

    private var chatAffordance: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
        return HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: hasUnreadChat ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: 40, height: 40)
                .background(.paeoniaAccentPrimary.opacity(0.16), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(hasUnreadChat ? .dailyChatCardUnreadTitle(participants.partnerName) : .dailyChatCardOpen)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                if let lastMessagePreview, !lastMessagePreview.isEmpty {
                    Text(verbatim: lastMessagePreview)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(hasUnreadChat ? Color.paeoniaTextPrimary : Color.paeoniaTextSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasUnreadChat {
                Circle()
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary, in: shape)
        .overlay {
            shape.strokeBorder(
                hasUnreadChat ? Color.paeoniaAccentPrimary : Color.paeoniaSurfacePressed,
                lineWidth: hasUnreadChat ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chatAccessibilityLabel)
    }

    private var chatAccessibilityLabel: Text {
        let title = hasUnreadChat
            ? Text(.dailyChatCardUnreadTitle(participants.partnerName))
            : Text(.dailyChatCardPreview)
        if let lastMessagePreview, !lastMessagePreview.isEmpty {
            return Text("\(title): \(Text(verbatim: lastMessagePreview))")
        }
        return hasUnreadChat ? title : Text(.dailyChatCardOpen)
    }

    /// Only a revealed partner answer gets the contextual action. Passing its id into
    /// the existing flow lets the backend preserve the objectionable answer itself.
    private var reportablePartnerAnswerID: UUID? {
        guard let detail = question.partnerAnswerDetail, detail.canViewAnswer else {
            return nil
        }
        return detail.answerID
    }

    /// The same primary CTA the daily prompt card uses. When the user still has their
    /// own questions to finish it stays visible but disabled, so it reads as a clear
    /// "do yours first" rather than disappearing.
    private var answerButton: some View {
        Button(action: onAnswer) {
            Text(canOpenAnswerFlow ? .dailyChallengePartnerAnswerCta : .dailyChallengePartnerLockedCta)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canOpenAnswerFlow)
    }

    private var lockedPartnerAnswerHint: some View {
        Text(.dailyChallengePartnerHiddenMessage(participants.partnerName))
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
