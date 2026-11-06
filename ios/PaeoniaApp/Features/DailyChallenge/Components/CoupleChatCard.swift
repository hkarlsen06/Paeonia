import SwiftUI

/// The couple chat ("Just us"), pinned above everything else on the Chats tab. Both partners'
/// faces, the newest message ("You: ..." or "Robin: ..."), or a line that invites the first
/// message. It glows while a message from the partner waits, like the other cards that need
/// this person. It reads the phone's chat summaries, so it is complete on the first frame.
struct CoupleChatCard: View {
    let participants: DailyChallengeParticipants
    /// The chat once someone has written in it.
    let summary: ThreadChatSummary?
    let isUnread: Bool
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 48
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)

    var body: some View {
        Button(action: onOpen) { card }
            .buttonStyle(.paeoniaPressableCard)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("chats.coupleChat")
    }

    private var card: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    avatars
                    HStack(spacing: PaeoniaSpacing.space12) {
                        textContent
                        accessory
                    }
                }
            } else {
                HStack(spacing: PaeoniaSpacing.space12) {
                    avatars
                    textContent
                    accessory
                }
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paeoniaCardSurface(in: shape, fill: background, needsAttention: isUnread)
        .contentShape(shape)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(.chatsCoupleChatTitle)
                .font(PaeoniaTypography.collectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
            if isUnread {
                Text(.dailyChatCardUnreadTitle(participants.partnerName))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            Text(verbatim: previewLine)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The card blends toward both partners' petal colors, so it reads as the couple's own place
    /// and not as one more question. The pink border stays reserved for "waiting for you".
    private var background: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.paeoniaSurfaceSecondary.mix(with: .paeoniaPartnerOne, by: 0.38),
                Color.paeoniaSurfaceSecondary.mix(with: .paeoniaPartnerTwo, by: 0.30),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The two faces side by side, the partner's slightly over the user's.
    private var avatars: some View {
        HStack(spacing: -avatarSize * 0.35) {
            PaeoniaCoupleAvatar(
                mediaAssetID: participants.currentProfilePhotoAssetID,
                name: participants.currentDisplayName ?? String(localized: .chatsCoupleChatYou),
                tint: .paeoniaPartnerOne,
                size: avatarSize,
                isCurrentUser: true
            )
            PaeoniaCoupleAvatar(
                mediaAssetID: participants.partnerProfilePhotoAssetID,
                name: participants.partnerName,
                tint: .paeoniaPartnerTwo,
                size: avatarSize,
                isCurrentUser: false
            )
            .background(Circle().fill(Color.paeoniaSurfaceSecondary).padding(-2))
        }
        .overlay(alignment: .bottom) { heart }
        .padding(.bottom, avatarSize * 0.18)
        .accessibilityHidden(true)
    }

    /// A small heart where the two faces meet.
    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: avatarSize * 0.26, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: avatarSize * 0.44, height: avatarSize * 0.44)
            .background(Circle().fill(Color.paeoniaAccentPrimary))
            .overlay(Circle().strokeBorder(Color.paeoniaSurfaceSecondary, lineWidth: 2))
            .offset(y: avatarSize * 0.22)
            .accessibilityHidden(true)
    }

    private var accessory: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            if isUnread {
                Circle()
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: 10, height: 10)
            }
            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
        }
        .accessibilityHidden(true)
    }

    /// "Robin: Miss you" for the newest message, or the line that invites the first one.
    private var previewLine: String {
        guard let summary, let text = summary.lastMessagePreview else {
            return String(localized: .chatsCoupleChatEmpty(participants.partnerName))
        }
        let name = summary.lastMessageSenderUserID == participants.currentUserID
            ? String(localized: .chatsCoupleChatYou)
            : participants.partnerName
        return String(localized: .chatsCoupleChatPreview(name, text))
    }

    private var accessibilityLabel: Text {
        var parts = [String(localized: .chatsCoupleChatAccessibilityLabel(participants.partnerName))]
        if isUnread { parts.append(String(localized: .dailyChatCardUnreadTitle(participants.partnerName))) }
        parts.append(previewLine)
        return Text(verbatim: parts.joined(separator: ". "))
    }
}
