import SwiftUI

/// A row for the chat about a memory or a story, in the same list as the question rows:
/// the photo, what it is ("Memory", "Robin's story"), its title or caption, and the newest
/// message. Tapping it opens the chat.
struct SubjectConversationCard: View {
    let conversation: SubjectConversation
    let people: StoryPeople
    let onOpen: () -> Void

    private static let photoSize: CGFloat = 56

    private var header: ThreadChatHeader { conversation.header(people: people) }

    var body: some View {
        Button(action: onOpen) { card }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.conversation.\(conversation.id.uuidString.lowercased())")
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
                thumbnail
                    .frame(width: Self.photoSize, height: Self.photoSize)
                    .accessibilityHidden(true)

                labels
                    .frame(maxWidth: .infinity, alignment: .leading)

                accessory
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The photo, or for a memory with only notes, the Memories tab's mark.
    @ViewBuilder
    private var thumbnail: some View {
        if let photoAssetID = header.photoAssetID {
            MemoryMediaImageView(
                mediaAssetID: photoAssetID,
                height: Self.photoSize,
                cornerRadius: PaeoniaRadius.radius12,
                allowsViewing: false
            )
        } else {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
                .overlay {
                    Image(
                        systemName: header.gameSource == nil ? MainTab.memories.systemImage : MainTab.games.systemImage
                    )
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaMemory)
                        .accessibilityHidden(true)
                }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(verbatim: header.eyebrow)
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

    /// The memory's title or the story's caption, else what it is and when.
    private var title: Text {
        if let title = header.title.trimmedNonEmpty {
            return Text(verbatim: title)
        }
        switch conversation.subject {
        case .memory:
            return Text(.questionsMemoryChatUntitled(header.detail ?? ""))
        case .story(let story):
            let posted = story.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
            return Text(.questionsStoryChatUntitled(posted))
        case .game(let source):
            return Text(source.kind.name)
        }
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
