import ExyteChat
import SwiftUI

/// The union of a row's swipeable payload frames, so your own rows know where the
/// empty space left of the bubble ends.
struct ThreadChatPayloadFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard !next.isEmpty else { return }
        value = value.isEmpty ? next : value.union(next)
    }
}

/// Rounded bubbles whose corners tighten where they join the next or previous
/// message from the same person.
enum ThreadChatBubbleShape {
    private static let radius: CGFloat = 20
    private static let joinedRadius: CGFloat = 6

    static func shape(for context: ThreadChatGroupContext) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: !context.isCurrentUser && context.joinsPrevious ? joinedRadius : radius,
                bottomLeading: !context.isCurrentUser && context.joinsNext ? joinedRadius : radius,
                bottomTrailing: context.isCurrentUser && context.joinsNext ? joinedRadius : radius,
                topTrailing: context.isCurrentUser && context.joinsPrevious ? joinedRadius : radius
            ),
            style: .continuous
        )
    }
}

/// The message a reply answers, shown small above the reply. Tapping it jumps there.
struct ThreadChatQuotedMessage: View {
    let preview: ThreadChatReplyPreview
    let isCurrentUser: Bool
    let maxWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: 3)
                ThreadChatReplyPreviewContent(preview: preview, snippetLineLimit: 2)
            }
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space4 + 2)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                .paeoniaSurfaceSecondary.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: maxWidth, alignment: isCurrentUser ? .trailing : .leading)
        .accessibilityHint(Text(.dailyChatReplyJumpHint))
    }
}

/// Who wrote the quoted message and what it said.
struct ThreadChatReplyPreviewContent: View {
    let preview: ThreadChatReplyPreview
    let snippetLineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: preview.senderName)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
            snippet
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(snippetLineLimit)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var snippet: some View {
        if !preview.photos.isEmpty {
            HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                ThreadChatPhotoThumbnails(photos: preview.photos)
                if let text = preview.snippet?.trimmedNonEmpty {
                    Text(verbatim: text)
                }
            }
        } else if preview.isVoice {
            Label {
                Text(.dailyChatVoicePreview)
            } icon: {
                Image(systemName: "waveform")
            }
        } else if preview.isDeleted {
            Text(.dailyChatReplyDeleted)
        } else if let text = preview.snippet {
            Text(verbatim: text)
        } else if preview.isAnswer {
            Text(.dailyChatReplyAnswerUnavailable)
        } else {
            Text(.dailyChatReplyUnavailable)
        }
    }
}

/// The day between groups of messages, like Tidex's separator.
struct ThreadChatDateSeparator: View {
    let date: Date

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            rule
            Text(label)
                .font(.caption2)
                .foregroundStyle(.paeoniaTextTertiary)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            rule
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space8)
    }

    private var rule: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: .dailyChatDateToday) }
        if calendar.isDateInYesterday(date) { return String(localized: .dailyChatDateYesterday) }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

extension View {
    @ViewBuilder
    func frameGetterIfNeeded(_ frame: Binding<CGRect>?) -> some View {
        if let frame {
            frameGetter(frame)
        } else {
            self
        }
    }
}

/// Three dots that rise and fade in turn while the partner types. They hold still
/// under Reduce Motion. Tidex's timing: 0.5 seconds a beat, 0.15 seconds apart.
struct ThreadChatTypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRaised = [false, false, false]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.paeoniaTextTertiary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(reduceMotion || isRaised[index] ? 1 : 0.5)
                    .opacity(reduceMotion || isRaised[index] ? 1 : 0.4)
            }
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .onAppear {
            guard !reduceMotion else { return }
            for index in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15)
                ) {
                    isRaised[index] = true
                }
            }
        }
    }
}

extension DailyChallengeParticipants {
    /// Who is who, for the words that say who reacted.
    var reactionParticipants: ReactionParticipants {
        ReactionParticipants(currentUserID: currentUserID, partnerName: partnerName)
    }
}
