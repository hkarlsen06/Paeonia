import SwiftUI

/// Every story the couple shared, newest first, so a story stays after it leaves Home.
/// Opened from the Stories row at the top of Memories.
struct StoriesArchiveView: View {
    let viewModel: StoriesViewModel
    let people: StoryPeople

    @State private var viewer: StoryViewerContent?
    @Environment(\.threadChatContext) private var chatContext

    private static let tileHeight: CGFloat = 180
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: PaeoniaSpacing.space8)]

    var body: some View {
        content
            .paeoniaTabBackdrop()
            .navigationTitle(Text(.storiesArchiveTitle))
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $viewer) { content in
                StoryViewer(content: content, people: people, viewModel: viewModel)
                    .analyticsScreen("story_viewer")
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.stories.isEmpty {
            PaeoniaEmptyStateView(
                title: .storiesArchiveEmptyTitle,
                message: .storiesArchiveEmptyMessage(people.partnerName),
                systemImage: "circle.dashed"
            )
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: PaeoniaSpacing.space8) {
                    ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { position, story in
                        Button {
                            viewer = StoryViewerContent(
                                stories: viewModel.stories,
                                startIndex: position,
                                mode: .archive
                            )
                        } label: {
                            tile(story)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space16)
                .paeoniaReadableWidth()
            }
        }
    }

    private func tile(_ story: Story) -> some View {
        MemoryMediaImageView(
            mediaAssetID: story.mediaAssetID,
            height: Self.tileHeight,
            cornerRadius: PaeoniaRadius.radius12,
            allowsViewing: false
        )
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: PaeoniaSpacing.space4) {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: people.photoAssetID(of: story),
                    name: people.name(of: story),
                    tint: people.tint(of: story),
                    size: 20
                )
                Text(story.createdAt, format: .dateTime.day().month(.abbreviated))
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .padding(PaeoniaSpacing.space8)
        }
        .overlay(alignment: .bottomTrailing) {
            StoredReactionBadge(target: .story(story.id))
                .padding(PaeoniaSpacing.space4)
        }
        .overlay(alignment: .topTrailing) { repliesMark(for: story) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(.storiesArchiveTileAccessibility(
                people.name(of: story),
                story.createdAt.formatted(date: .abbreviated, time: .omitted)
            ))
        )
        .accessibilityValue(
            chatContext.summaries?.summary(for: .story(story.id)) != nil
                ? Text(.storiesArchiveTileReplies)
                : Text(verbatim: "")
        )
        .accessibilityAddTraits(.isButton)
    }
}

extension StoriesArchiveView {
    /// A story with replies says so, with a dot when the partner wrote one not read yet.
    @ViewBuilder
    fileprivate func repliesMark(for story: Story) -> some View {
        if chatContext.summaries?.summary(for: .story(story.id)) != nil {
            repliesBubble(isUnread: chatContext.summaries?.isUnread(.story(story.id)) ?? false)
        }
    }

    private func repliesBubble(isUnread: Bool) -> some View {
        Image(systemName: "bubble.left.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(PaeoniaSpacing.space8)
            .background(.black.opacity(0.45), in: Circle())
            .overlay(alignment: .topTrailing) {
                if isUnread {
                    Circle()
                        .fill(.paeoniaAccentPrimary)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(PaeoniaSpacing.space4)
            .accessibilityHidden(true)
    }
}

/// The way into the Stories archive, at the top of the Memories timeline.
struct MemoriesStoriesRow: View {
    let stories: [Story]
    let action: () -> Void

    private static let thumbnailSize: CGFloat = 40

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaeoniaSpacing.space12) {
                thumbnails
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(.storiesArchiveTitle)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Text(.storiesArchiveRowCount(stories.count))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
            .padding(PaeoniaSpacing.space12)
            .background(
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .fill(.paeoniaSurfacePrimary)
            )
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// The newest three, overlapping.
    private var thumbnails: some View {
        HStack(spacing: -Self.thumbnailSize / 2) {
            ForEach(stories.prefix(3)) { story in
                MemoryMediaImageView(
                    mediaAssetID: story.mediaAssetID,
                    height: Self.thumbnailSize,
                    cornerRadius: Self.thumbnailSize / 2,
                    allowsViewing: false
                )
                .frame(width: Self.thumbnailSize)
                .overlay(Circle().strokeBorder(.paeoniaBackgroundPrimary, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
