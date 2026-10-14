import ExyteChat
import SwiftUI

/// One row of a question's chat: Paeonia's question, an answer, or a message. Ported
/// from Tidex's chat row, so it has the same gestures. Swipe a message toward the
/// middle to reply, swipe left anywhere to slide the bubbles over and show their
/// times, and the row's corners join with the messages around it.
struct DailyChatMessageRow: View {
    private static let maximumBubbleWidth: CGFloat = 360
    private static let avatarSize: CGFloat = 28
    private static let resetAnimationDuration: TimeInterval = 0.18

    let row: DailyChatRow
    let participants: DailyChallengeParticipants
    let mediaKind: DailyChallengeAnswerKind
    let isHighlighted: Bool
    /// Nil when this row can't be replied to.
    let onReply: (() -> Void)?
    let onRetry: () -> Void
    let onTapQuoted: (UUID) -> Void
    var onOpenPhoto: (DailyQuestionChatPhoto) -> Void = { _ in }
    @Binding var timestampRevealOffset: CGFloat
    /// Set while ExyteChat shows this row above its long-press menu.
    let messageFrame: Binding<CGRect>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replySwipeOffset: CGFloat = 0
    @State private var isReplySwipeActive = false
    @State private var hasCrossedReplyThreshold = false
    @State private var rowFrame: CGRect = .zero
    @State private var payloadFrame: CGRect = .zero

    private var isCurrentUser: Bool { row.isCurrentUser }
    private var groupContext: DailyChatGroupContext { row.groupContext }
    /// The long-press menu shows a still copy of the row, so its gestures stay off.
    private var isInMenu: Bool { messageFrame != nil }

    var body: some View {
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
    private var payload: some View {
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
        case let .answer(answer):
            bubble(fill: bubbleFill) {
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
            .accessibilityElement(children: .contain)
        case let .message(message):
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                if let quoted = row.quotedPreview {
                    DailyChatQuotedMessage(
                        preview: quoted,
                        isCurrentUser: isCurrentUser,
                        maxWidth: bubbleMaxWidth,
                        onTap: { onTapQuoted(quoted.messageID) }
                    )
                    .allowsHitTesting(!isInMenu)
                }
                // The width limit goes outside the swipe area, so the area is only as
                // wide as the bubble and the space beside it stays free for the times.
                replySwipeContainer {
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
                .frame(maxWidth: bubbleMaxWidth, alignment: isCurrentUser ? .trailing : .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text(.dailyChatActionReply)) { onReply?() }
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

    private func bubble(fill: Color, @ViewBuilder content: () -> some View) -> some View {
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

// MARK: - Gestures

extension DailyChatMessageRow {
    // MARK: - Times

    private func timestampRevealContainer(@ViewBuilder content: () -> some View) -> some View {
        ZStack(alignment: .trailing) {
            timestampColumn
            content()
                .offset(x: isCurrentUser ? -timestampRevealOffset : 0)
        }
        .background { frameReader { rowFrame = $0 } }
        .overlay(alignment: isCurrentUser ? .leading : .trailing) {
            if !isInMenu {
                DailyChatHorizontalPanSurface(
                    targetKind: .timestampRevealGutter,
                    minimumDistance: DailyChatTimestampRevealResolver.minimumDistance,
                    direction: .left,
                    onChanged: handleTimestampRevealChanged,
                    onEnded: handleTimestampRevealEnded
                )
                .frame(width: timestampSurfaceWidth, height: max(rowFrame.height, 1))
            }
        }
        .onPreferenceChange(DailyChatPayloadFrameKey.self) { payloadFrame = $0 }
    }

    @ViewBuilder
    private var timestampColumn: some View {
        if row.message == nil, !row.isAnswer {
            Color.clear.frame(width: 0)
        } else {
            Text(row.createdAt, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.paeoniaTextTertiary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: DailyChatTimestampRevealResolver.revealWidth, alignment: .trailing)
                .padding(.trailing, PaeoniaSpacing.space12)
                .opacity(min(max(timestampRevealOffset / DailyChatTimestampRevealResolver.revealWidth, 0), 1))
                .allowsHitTesting(false)
                // The time only shows while swiping. VoiceOver reads the row instead.
                .accessibilityHidden(true)
        }
    }

    /// Your messages take the swipe in the empty space left of the bubble, so the
    /// bubble's own reply swipe keeps working. Other rows take it everywhere, because
    /// their reply swipe goes the other way or they have none.
    private var timestampSurfaceWidth: CGFloat {
        let sharesSwipe = isCurrentUser && onReply != nil && row.message != nil
        guard rowFrame.width > 0 else { return sharesSwipe ? PaeoniaSpacing.space40 : 0 }
        guard sharesSwipe else { return rowFrame.width }
        guard payloadFrame.width > 0 else { return PaeoniaSpacing.space40 }
        return max(min(payloadFrame.minX - rowFrame.minX, rowFrame.width), 0)
    }

    private func handleTimestampRevealChanged(_ value: DailyChatDragValue) {
        guard let offset = DailyChatTimestampRevealResolver.clampedRevealOffset(
            horizontal: value.translation.width,
            vertical: value.translation.height
        ) else { return }
        timestampRevealOffset = offset
    }

    private func handleTimestampRevealEnded(_ value: DailyChatDragValue) {
        handleTimestampRevealChanged(value)
        guard timestampRevealOffset != 0 else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: Self.resetAnimationDuration)) {
            timestampRevealOffset = 0
        }
    }

    // MARK: - Reply swipe

    private var replyDirection: DailyChatSwipeDirection {
        isCurrentUser ? .left : .right
    }

    @ViewBuilder
    private func replySwipeContainer(@ViewBuilder content: () -> some View) -> some View {
        if onReply != nil, !isInMenu {
            content()
                .background { frameReader(preference: true) }
                .contentShape(Rectangle())
                .overlay {
                    DailyChatHorizontalPanSurface(
                        targetKind: .replyPayload(direction: replyDirection),
                        minimumDistance: DailyChatReplySwipeResolver.minimumDistance,
                        direction: replyDirection,
                        onChanged: handleReplySwipeChanged,
                        onEnded: handleReplySwipeEnded
                    )
                }
                .overlay(alignment: isCurrentUser ? .trailing : .leading) {
                    replyActionLabel
                        .offset(x: isCurrentUser ? 48 : -48)
                        .allowsHitTesting(false)
                }
                .offset(x: replySwipeOffset)
                .sensoryFeedback(.impact(weight: .medium), trigger: hasCrossedReplyThreshold) { _, crossed in
                    crossed
                }
        } else {
            content()
                .background { frameReader(preference: true) }
        }
    }

    private var replyActionLabel: some View {
        let progress = min(abs(replySwipeOffset) / DailyChatReplySwipeResolver.actionWidth, 1)
        return Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.paeoniaTextInverse)
            .frame(width: 44, height: 32)
            .background(.paeoniaAccentPrimary, in: Capsule())
            .scaleEffect(0.7 + progress * 0.3)
            .opacity(isReplySwipeActive ? replyActionOpacity : 0)
            .accessibilityHidden(true)
    }

    private var replyActionOpacity: Double {
        min(abs(replySwipeOffset) / (DailyChatReplySwipeResolver.actionWidth * 0.6), 1)
    }

    private func handleReplySwipeChanged(_ value: DailyChatDragValue) {
        guard let offset = DailyChatReplySwipeResolver.clampedOffset(
            horizontal: value.translation.width,
            vertical: value.translation.height,
            allowedDirection: replyDirection
        ) else { return }
        isReplySwipeActive = offset != 0
        replySwipeOffset = offset
        if DailyChatReplySwipeResolver.crossedThreshold(offset: offset), !hasCrossedReplyThreshold {
            hasCrossedReplyThreshold = true
        }
    }

    private func handleReplySwipeEnded(_ value: DailyChatDragValue) {
        let finalOffset = replySwipeOffset
        hasCrossedReplyThreshold = false
        guard finalOffset != 0 else {
            isReplySwipeActive = false
            return
        }
        let outcome = DailyChatReplySwipeResolver.outcome(
            offset: finalOffset,
            velocity: value.velocity.width,
            allowedDirection: replyDirection
        )
        withAnimation(.easeOut(duration: Self.resetAnimationDuration)) {
            replySwipeOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetAnimationDuration) {
            isReplySwipeActive = false
        }
        guard outcome == .trigger, let onReply else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetAnimationDuration + 0.04) {
            onReply()
        }
    }

    // MARK: - Frames

    /// Reports this view's global frame, either to `onChange` or as the payload frame.
    private func frameReader(preference: Bool = false, onChange: ((CGRect) -> Void)? = nil) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .preference(key: DailyChatPayloadFrameKey.self, value: preference ? frame : .zero)
                .onAppear { onChange?(frame) }
                .onChange(of: frame) { _, newFrame in onChange?(newFrame) }
        }
    }
}
