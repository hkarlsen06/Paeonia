import SwiftUI

/// The message field under the partner's story, like a story reply on Instagram. Sending
/// queues the reply in the story's chat. The button next to it opens the whole conversation
/// once there is one.
struct StoryReplyBar: View {
    let partnerName: String
    @Bindable var replies: StoryReplies
    var isFocused: FocusState<Bool>.Binding
    let hasConversation: Bool
    let hasUnreadReply: Bool
    let onSend: () -> Void
    let onOpenReplies: () -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            field
            if hasConversation {
                StoryRepliesButton(isUnread: hasUnreadReply, action: onOpenReplies)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if replies.justSent {
            Label {
                Text(.storiesViewerReplySent)
            } icon: {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(0.15), in: Capsule())
            .transition(.opacity)
        } else {
            HStack(spacing: PaeoniaSpacing.space8) {
                TextField(
                    text: $replies.draft,
                    prompt: Text(.storiesViewerReplyPlaceholder(partnerName)).foregroundStyle(.white.opacity(0.7))
                ) {
                    Text(.storiesViewerReplyPlaceholder(partnerName))
                }
                .font(PaeoniaTypography.body)
                .foregroundStyle(.white)
                .tint(.white)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
                if replies.canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.storiesViewerReplySend))
                }
            }
            .padding(.horizontal, PaeoniaSpacing.space16)
            .frame(minHeight: 44)
            .background(.white.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
    }
}

/// Opens the replies to a story. A dot says the other person wrote one the user has not read.
struct StoryRepliesButton: View {
    let isUnread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if isUnread {
                        Circle()
                            .fill(.paeoniaAccentPrimary)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.storiesViewerRepliesOpenAccessibility))
        .accessibilityValue(isUnread ? Text(.storiesViewerRepliesUnread) : Text(verbatim: ""))
    }
}
