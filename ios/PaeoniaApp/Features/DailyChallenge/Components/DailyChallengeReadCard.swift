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

/// A short row for one question in a list: the question, who has answered, and what
/// happens next. The answers themselves live on the question's own page, so tapping
/// a row you have answered opens that page, where the answers start the chat.
///
/// A partner question the user can still answer opens the answer flow instead, and
/// is the zoom source for it. That stays locked until the user finishes their own
/// three. A row whose answer is still saving shows what was saved.
struct DailyChallengeReadCard: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()
    var sending: DailySendingPreview?
    var isOwnChallengeComplete = true
    var zoomNamespace: Namespace.ID?
    var isHighlighted = false
    var onAnswer: () -> Void = {}
    var lastMessagePreview: String?
    var hasUnreadChat = false
    /// The user can read the partner's answer and hasn't seen it yet.
    var hasNewPartnerAnswer = false
    /// Opens the question's page. Only a question the user has answered has one.
    var onOpen: (() -> Void)?

    /// A partner question the user can still answer to reveal the reply. When sending,
    /// the row shows the "saved, sending" preview instead, so this stays false.
    private var isAnswerable: Bool {
        sending == nil && question.origin == .partner && question.isAvailableToAnswer
    }

    /// Answering a partner's question is gated behind finishing your own three first.
    private var canOpenAnswerFlow: Bool {
        isAnswerable && isOwnChallengeComplete
    }

    private var opensPage: Bool {
        sending == nil && question.hasOwnAnswer && onOpen != nil
    }

    private var isUnread: Bool {
        hasUnreadChat && question.isChatAvailable
    }

    /// Something from the partner to look at: a chat message or their answer.
    private var isNew: Bool {
        isUnread || (hasNewPartnerAnswer && question.isChatAvailable)
    }

    var body: some View {
        Group {
            if canOpenAnswerFlow {
                Button(action: onAnswer) { card }
                    .buttonStyle(.plain)
            } else if opensPage, let onOpen {
                Button(action: onOpen) { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        // Answerable rows are the source the single-question flow zooms out of, so the
        // tapped row appears to grow into the full-screen flow.
        .zoomSource(question.id, in: canOpenAnswerFlow ? zoomNamespace : nil)
        .overlay {
            let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
            if isHighlighted {
                shape.stroke(.paeoniaAccentPrimary, lineWidth: 2)
            } else if isNew {
                shape.strokeBorder(.paeoniaAccentPrimary, lineWidth: PaeoniaRadius.strokeEmphasis)
            }
        }
    }

    private var card: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                Text(question.prompt)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let sending {
                    // Still saving: shows whatever was saved (photo, pick, and/or
                    // caption), so a status line would only repeat it.
                    DailySendingAnswerView(
                        mediaKind: sending.mediaKind,
                        mediaData: sending.mediaData,
                        voiceDurationMs: sending.voiceDurationMs,
                        partnerChoiceName: sending.partnerChoiceName,
                        text: sending.text
                    )
                } else {
                    statusRow
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusRow: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            DailyAnswerersView(question: question, participants: participants)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                statusText
                    .font(isNew ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.caption)
                    .foregroundStyle(isNew ? Color.paeoniaTextPrimary : Color.paeoniaTextSecondary)
                    .lineLimit(3)

                if isUnread, let preview = lastMessagePreview?.trimmedNonEmpty {
                    Text(verbatim: preview)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
    }

    /// What the row says about the question, in the order the cases can happen.
    private var statusText: Text {
        if isAnswerable {
            return Text(canOpenAnswerFlow
                ? .dailyChallengePartnerHiddenMessage(participants.partnerName)
                : .dailyChallengePartnerLockedCta)
        }
        guard question.hasOwnAnswer else { return Text(.dailyChallengeNotAnswered) }
        guard question.hasPartnerAnswer else { return Text(.dailyChallengeRowWaiting(participants.partnerName)) }
        guard question.isChatAvailable else { return Text(.dailyChallengePartnerHidden(participants.partnerName)) }
        if isUnread { return Text(.dailyChatCardUnreadTitle(participants.partnerName)) }
        if isNew { return Text(.dailyChallengeRowNewPartnerAnswer(participants.partnerName)) }
        if let preview = lastMessagePreview?.trimmedNonEmpty { return Text(verbatim: preview) }
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
            if isAnswerable, !canOpenAnswerFlow {
                Image(systemName: "lock.fill")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
            } else if canOpenAnswerFlow || opensPage {
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

    private let size: CGFloat = 28

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            avatar(
                photo: participants.partnerProfilePhotoAssetID,
                name: participants.partnerName,
                tint: .paeoniaPartnerTwo,
                answered: question.hasPartnerAnswer
            )
            avatar(
                photo: participants.currentProfilePhotoAssetID,
                name: participants.currentDisplayName ?? String(localized: .dailyChallengeChoiceYou),
                tint: .paeoniaPartnerOne,
                answered: question.hasOwnAnswer
            )
        }
        .accessibilityHidden(true)
    }

    private func avatar(photo: UUID?, name: String, tint: Color, answered: Bool) -> some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: photo, name: name, tint: tint, size: size)
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
