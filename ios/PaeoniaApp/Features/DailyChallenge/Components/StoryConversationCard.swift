import SwiftUI

/// A row for the chat about a story, in the same list as the question rows: the story's
/// photo, whose story it is, its caption, and the newest message. Tapping it opens the chat.
struct StoryConversationCard: View {
    let conversation: StoryConversation
    let people: StoryPeople
    let onOpen: () -> Void

    private static let photoSize: CGFloat = 56

    private var story: Story { conversation.story }

    var body: some View {
        Button(action: onOpen) { card }
            .buttonStyle(.plain)
            .overlay {
                if conversation.isUnread {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                        .strokeBorder(.paeoniaAccentPrimary, lineWidth: PaeoniaRadius.strokeEmphasis)
                }
            }
    }

    private var card: some View {
        PaeoniaCard {
            HStack(spacing: PaeoniaSpacing.space12) {
                MemoryMediaImageView(
                    mediaAssetID: story.mediaAssetID,
                    height: Self.photoSize,
                    cornerRadius: PaeoniaRadius.radius12,
                    allowsViewing: false
                )
                .frame(width: Self.photoSize)
                .accessibilityHidden(true)

                labels
                    .frame(maxWidth: .infinity, alignment: .leading)

                accessory
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(people.isOwn(story) ? .chatHeaderYourStory : .chatHeaderStory(people.partnerName))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
            title
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(2)
            if conversation.isUnread {
                Text(.dailyChatCardUnreadTitle(people.partnerName))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            if let preview = conversation.summary.lastMessagePreview {
                Text(verbatim: preview)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var title: Text {
        if let caption = story.caption?.trimmedNonEmpty {
            return Text(verbatim: caption)
        }
        let posted = story.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return Text(.questionsStoryChatUntitled(posted))
    }

    private var accessory: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            if conversation.isUnread {
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
}
