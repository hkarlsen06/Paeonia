import SwiftUI

// MARK: - Gestures

extension ThreadChatMessageRow {
    // MARK: - Times

    func timestampRevealContainer(@ViewBuilder content: () -> some View) -> some View {
        ZStack(alignment: .trailing) {
            timestampColumn
            content()
                .offset(x: isCurrentUser ? -timestampReveal.offset : 0)
        }
        .background { frameReader { rowFrame = $0 } }
        .overlay(alignment: isCurrentUser ? .leading : .trailing) {
            if !isInMenu {
                ThreadChatHorizontalPanSurface(
                    targetKind: .timestampRevealGutter,
                    minimumDistance: ThreadChatTimestampRevealResolver.minimumDistance,
                    direction: .left,
                    onChanged: handleTimestampRevealChanged,
                    onEnded: handleTimestampRevealEnded
                )
                .frame(width: timestampSurfaceWidth, height: max(rowFrame.height, 1))
            }
        }
        .onPreferenceChange(ThreadChatPayloadFrameKey.self) { payloadFrame = $0 }
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
                .frame(width: ThreadChatTimestampRevealResolver.revealWidth, alignment: .trailing)
                .padding(.trailing, PaeoniaSpacing.space12)
                .opacity(min(max(timestampReveal.offset / ThreadChatTimestampRevealResolver.revealWidth, 0), 1))
                .allowsHitTesting(false)
                // The time only shows while swiping. VoiceOver reads the row instead.
                .accessibilityHidden(true)
        }
    }

    /// Your messages take the swipe in the empty space left of the bubble, so the
    /// bubble's own reply swipe keeps working. Other rows take it everywhere, because
    /// their reply swipe goes the other way or they have none.
    private var timestampSurfaceWidth: CGFloat {
        let sharesSwipe = isCurrentUser && onReply != nil && (row.message != nil || row.isAnswer)
        guard rowFrame.width > 0 else { return sharesSwipe ? PaeoniaSpacing.space40 : 0 }
        guard sharesSwipe else { return rowFrame.width }
        guard payloadFrame.width > 0 else { return PaeoniaSpacing.space40 }
        return max(min(payloadFrame.minX - rowFrame.minX, rowFrame.width), 0)
    }

    private func handleTimestampRevealChanged(_ value: ThreadChatDragValue) {
        guard let offset = ThreadChatTimestampRevealResolver.clampedRevealOffset(
            horizontal: value.translation.width,
            vertical: value.translation.height
        ) else { return }
        timestampReveal.offset = offset
    }

    private func handleTimestampRevealEnded(_ value: ThreadChatDragValue) {
        handleTimestampRevealChanged(value)
        guard timestampReveal.offset != 0 else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: Self.resetAnimationDuration)) {
            timestampReveal.offset = 0
        }
    }

    // MARK: - Reply swipe

    private var replyDirection: ThreadChatSwipeDirection {
        isCurrentUser ? .left : .right
    }

    @ViewBuilder
    func replySwipeContainer(@ViewBuilder content: () -> some View) -> some View {
        if onReply != nil, !isInMenu {
            content()
                .background { frameReader(preference: true) }
                .contentShape(Rectangle())
                .overlay {
                    ThreadChatHorizontalPanSurface(
                        targetKind: .replyPayload(direction: replyDirection),
                        minimumDistance: ThreadChatReplySwipeResolver.minimumDistance,
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
        let progress = min(abs(replySwipeOffset) / ThreadChatReplySwipeResolver.actionWidth, 1)
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
        min(abs(replySwipeOffset) / (ThreadChatReplySwipeResolver.actionWidth * 0.6), 1)
    }

    private func handleReplySwipeChanged(_ value: ThreadChatDragValue) {
        guard let offset = ThreadChatReplySwipeResolver.clampedOffset(
            horizontal: value.translation.width,
            vertical: value.translation.height,
            allowedDirection: replyDirection
        ) else { return }
        isReplySwipeActive = offset != 0
        replySwipeOffset = offset
        if ThreadChatReplySwipeResolver.crossedThreshold(offset: offset), !hasCrossedReplyThreshold {
            hasCrossedReplyThreshold = true
        }
    }

    private func handleReplySwipeEnded(_ value: ThreadChatDragValue) {
        let finalOffset = replySwipeOffset
        hasCrossedReplyThreshold = false
        guard finalOffset != 0 else {
            isReplySwipeActive = false
            return
        }
        let outcome = ThreadChatReplySwipeResolver.outcome(
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
                .preference(key: ThreadChatPayloadFrameKey.self, value: preference ? frame : .zero)
                .onAppear { onChange?(frame) }
                .onChange(of: frame) { _, newFrame in onChange?(newFrame) }
        }
    }
}
