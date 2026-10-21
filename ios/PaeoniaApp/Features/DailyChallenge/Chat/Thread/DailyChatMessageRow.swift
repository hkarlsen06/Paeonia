import ExyteChat
import SwiftUI

/// One row of a question's chat: Paeonia's question, an answer, or a message. Ported
/// from Tidex's chat row, so it has the same gestures. Swipe a message or an answer
/// toward the middle to reply, swipe left anywhere to slide the bubbles over and show
/// their times, and the row's corners join with the messages around it. Reactions sit
/// on the bubble's top corner.
struct DailyChatMessageRow: View {
    private static let maximumBubbleWidth: CGFloat = 360
    private static let avatarSize: CGFloat = 28
    /// Room above a bubble with reactions, so the badge clears what is above it.
    private static let reactionClearance: CGFloat = 14
    static let resetAnimationDuration: TimeInterval = 0.18

    let row: DailyChatRow
    let participants: DailyChallengeParticipants
    let isHighlighted: Bool
    /// The partner's answer just opened after the user answered, so it plays its reveal.
    var isRevealing = false
    /// Nil when this row can't be replied to.
    let onReply: (() -> Void)?
    /// Puts an emoji on the message or answer. Nil on rows that can't get a reaction.
    var onReact: ((String) -> Void)?
    /// The user's own reaction on this row, for the VoiceOver actions.
    var ownReaction: String?
    let onRetry: () -> Void
    let onTapQuoted: (DailyChatItemID) -> Void
    var onOpenPhoto: (DailyQuestionChatPhoto) -> Void = { _ in }
    /// Read only by the row views, so a swipe redraws them and not the page around them.
    let timestampReveal: DailyChatTimestampReveal
    /// Set while ExyteChat shows this row above its long-press menu.
    let messageFrame: Binding<CGRect>?

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var replySwipeOffset: CGFloat = 0
    @State var isReplySwipeActive = false
    @State var hasCrossedReplyThreshold = false
    @State var rowFrame: CGRect = .zero
    @State var payloadFrame: CGRect = .zero

    var isCurrentUser: Bool { row.isCurrentUser }
    private var groupContext: DailyChatGroupContext { row.groupContext }
    /// The long-press menu shows a still copy of the row, so its gestures stay off.
    var isInMenu: Bool { messageFrame != nil }

    var body: some View {
        switch row.kind {
        case let .partnerChoiceMatch(match, celebrationID):
            PartnerChoiceMatchBanner(match: match, participants: participants, celebrationID: celebrationID)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
        case let .waiting(waiting):
            DailyChatWaitingNote(waiting: waiting, partnerName: participants.partnerName)
        default:
            bubbleRow
        }
    }

    private var bubbleRow: some View {
        timestampRevealContainer {
            HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                if !isCurrentUser {
                    avatarSlot
                }
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
                    payload
                    if hasStatusLine {
                        statusLine
                    }
                }
            }
            .padding(.horizontal, PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        }
        .padding(.top, groupContext.joinsPrevious ? 2 : PaeoniaSpacing.space4)
        .padding(.bottom, hasStatusLine ? 2 : (groupContext.joinsNext ? 2 : PaeoniaSpacing.space4))
        .background(isHighlighted ? Color.paeoniaAccentPrimary.opacity(0.14) : Color.clear)
    }

    // MARK: - Payloads

    @ViewBuilder
    var payload: some View {
        switch row.kind {
        case let .question(prompt):
            bubble(fill: .paeoniaSurfaceSecondary) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(.appTitle)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                    Text(verbatim: prompt)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        case let .answer(answer, mediaKind):
            replySwipeContainer {
                bubbleBody(fill: bubbleFill) {
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                        Label {
                            Text(isCurrentUser
                                ? .dailyChallengeYourAnswerTitle
                                : .dailyChatAnswerPartnerTitle(participants.partnerName))
                        } icon: {
                            Image(systemName: "quote.opening")
                        }
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(
                            isCurrentUser ? Color.paeoniaTextPrimary.opacity(0.72) : Color.paeoniaAccentPrimary
                        )

                        DailyAnswerContent(detail: answer, participants: participants, mediaKind: mediaKind)
                    }
                }
                .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) { reactionBadge }
                .dailyChatAnswerReveal(isActive: isRevealing, seed: row.id)
            }
            .padding(.top, reactionClearance)
            .frame(maxWidth: bubbleMaxWidth, alignment: isCurrentUser ? .trailing : .leading)
            .accessibilityElement(children: .contain)
            .accessibilityActions { itemAccessibilityActions }
        case let .message(message):
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                if let quoted = row.quotedPreview {
                    DailyChatQuotedMessage(
                        preview: quoted,
                        isCurrentUser: isCurrentUser,
                        maxWidth: bubbleMaxWidth,
                        onTap: { onTapQuoted(quoted.target) }
                    )
                    .allowsHitTesting(!isInMenu)
                }
                // The width limit goes outside the swipe area, so the area is only as
                // wide as the bubble and the space beside it stays free for the times.
                replySwipeContainer {
                    Group {
                        if message.voice != nil {
                            voicePayload(message)
                        } else if let photos = message.photos, !photos.isEmpty {
                            photoPayloads(photos, caption: message.body)
                        } else {
                            bubbleBody(fill: bubbleFill) {
                                messageText(message.body)
                            }
                        }
                    }
                    .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) { reactionBadge }
                }
                .padding(.top, reactionClearance)
                .frame(maxWidth: bubbleMaxWidth, alignment: isCurrentUser ? .trailing : .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityActions { itemAccessibilityActions }
        case .partnerChoiceMatch, .waiting:
            EmptyView()
        case .typing:
            bubble(fill: .paeoniaSurfacePrimary) {
                DailyChatTypingDots()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.dailyChatTyping(participants.partnerName)))
        }
    }

    private func messageText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Each photo is its own bubble, stacked and joined into one group with the caption
    /// last, like Tidex's photo messages.
    private func photoPayloads(_ photos: [DailyQuestionChatPhoto], caption: String) -> some View {
        let hasCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let count = photos.count + (hasCaption ? 1 : 0)
        return VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                DailyChatPhotoCard(
                    photo: photo,
                    size: DailyChatPhotoLayout.frameSize(for: photo),
                    shape: DailyChatBubbleShape.shape(for: payloadGroupContext(index: index, count: count)),
                    isCurrentUser: isCurrentUser
                )
                .frameGetterIfNeeded(index == count - 1 ? messageFrame : nil)
                .onTapGesture { if !isInMenu { onOpenPhoto(photo) } }
                .accessibilityAddTraits(.isButton)
            }
            if hasCaption {
                messageText(caption)
                    .padding(.horizontal, PaeoniaSpacing.space12 + 2)
                    .padding(.vertical, PaeoniaSpacing.space8 + 2)
                    .background(
                        bubbleFill,
                        in: DailyChatBubbleShape.shape(for: payloadGroupContext(index: count - 1, count: count))
                    )
                    .frameGetterIfNeeded(messageFrame)
            }
        }
    }

    /// The corners of one part of a message with several parts, joined to the parts
    /// around it and to the message's own group.
    private func payloadGroupContext(index: Int, count: Int) -> DailyChatGroupContext {
        let joinsPrevious = groupContext.joinsPrevious || index > 0
        let joinsNext = index < count - 1 || groupContext.joinsNext
        let position: DailyChatGroupPosition = switch (joinsPrevious, joinsNext) {
        case (false, false): .standalone
        case (false, true): .leading
        case (true, true): .middle
        case (true, false): .trailing
        }
        return DailyChatGroupContext(position: position, isCurrentUser: isCurrentUser)
    }

    private func voicePayload(_ message: DailyQuestionChatMessage) -> some View {
        Group {
            if let source = voiceSource(message) {
                DailyVoicePlaybackView(source: source, fallbackDurationMs: message.voice?.durationMs)
            } else {
                Text(.dailyChatVoicePreview)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .frame(width: 260)
        .background(bubbleFill, in: bubbleShape)
        .frameGetterIfNeeded(messageFrame)
    }

    private func voiceSource(_ message: DailyQuestionChatMessage) -> DailyVoiceSource? {
        if let data = message.voice?.data { return .data(data) }
        return message.voice?.mediaAssetID.map(DailyVoiceSource.mediaAsset)
    }

    func bubble(fill: Color, @ViewBuilder content: () -> some View) -> some View {
        bubbleBody(fill: fill, content: content)
            .frame(maxWidth: bubbleMaxWidth, alignment: isCurrentUser ? .trailing : .leading)
    }

    /// A bubble as wide as its content. The caller limits its width.
    private func bubbleBody(fill: Color, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, PaeoniaSpacing.space12 + 2)
            .padding(.vertical, PaeoniaSpacing.space8 + 2)
            .background(fill, in: bubbleShape)
            .frameGetterIfNeeded(messageFrame)
    }

    private var bubbleFill: Color {
        isCurrentUser ? .paeoniaAccentSecondary : .paeoniaSurfacePrimary
    }

    private var bubbleMaxWidth: CGFloat {
        DailyChatTimestampRevealResolver.contentMaxWidth(
            baseWidth: Self.maximumBubbleWidth,
            isCurrentUser: isCurrentUser
        )
    }

    private var bubbleShape: UnevenRoundedRectangle {
        DailyChatBubbleShape.shape(for: groupContext)
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if case .question = row.kind {
            Image(.paeoniaMark)
                .resizable()
                .scaledToFit()
                .padding(PaeoniaSpacing.space4)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .background(.paeoniaSurfaceSecondary, in: Circle())
                .padding(.top, 2)
                .accessibilityHidden(true)
        } else if groupContext.showsAvatar {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: participants.partnerProfilePhotoAssetID,
                name: participants.partnerName,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarSize
            )
            .padding(.top, 2)
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: Self.avatarSize, height: Self.avatarSize)
        }
    }
}

extension DailyChatMessageRow {
    // MARK: - Reactions and actions

    /// The reactions on the bubble's top corner, pushed out past its edge.
    @ViewBuilder
    var reactionBadge: some View {
        if !row.reactions.isEmpty {
            DailyChatReactionBadge(reactions: row.reactions, participants: participants)
                .offset(x: isCurrentUser ? -PaeoniaSpacing.space8 : PaeoniaSpacing.space8, y: -12)
        }
    }

    var reactionClearance: CGFloat {
        row.reactions.isEmpty ? 0 : Self.reactionClearance
    }

    /// Reply and the quick reactions, for VoiceOver and Voice Control. The long-press
    /// menu offers the same.
    @ViewBuilder
    var itemAccessibilityActions: some View {
        if let onReply {
            Button(action: onReply) { Text(.dailyChatActionReply) }
        }
        if let onReact {
            ForEach(DailyQuestionChatViewModel.quickReactions.filter { $0 != ownReaction }, id: \.self) { emoji in
                Button { onReact(emoji) } label: { Text(.dailyChatReactionAdd(emoji)) }
            }
            if let ownReaction {
                Button { onReact(ownReaction) } label: { Text(.dailyChatReactionRemove) }
            }
        }
    }

    // MARK: - Status

    private var isEdited: Bool {
        row.message?.editedAt != nil
    }

    private var hasStatusLine: Bool {
        row.status != nil || isEdited
    }

    /// The one small line under a bubble. Edited shares it with the delivery state, so
    /// an edited message never gets a second line, and the state keeps its place at
    /// the bubble's edge.
    private var statusLine: some View {
        HStack(spacing: 0) {
            if isEdited {
                editedMark
            }
            if let status = row.status {
                statusView(status)
            }
        }
    }

    private var editedMark: some View {
        Text(.dailyChatStatusEdited)
            .font(.caption2)
            .foregroundStyle(.paeoniaTextTertiary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, PaeoniaSpacing.space4)
    }

    @ViewBuilder
    private func statusView(_ status: DailyChatMessageStatus) -> some View {
        HStack(spacing: 3) {
            switch status {
            case .sending:
                ProgressView().controlSize(.mini)
                Text(.dailyChatStatusSending)
            case .sent:
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Text(.dailyChatStatusSent)
            case .read:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                Text(.dailyChatStatusRead)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.paeoniaError)
                    .accessibilityHidden(true)
                Text(.dailyChatStatusFailed)
                    .foregroundStyle(.paeoniaError)
                Button(action: onRetry) {
                    Text(.commonTryAgain)
                        .foregroundStyle(.paeoniaAccentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isInMenu)
            }
        }
        .font(.caption2)
        .foregroundStyle(.paeoniaTextTertiary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, PaeoniaSpacing.space4)
    }
}
