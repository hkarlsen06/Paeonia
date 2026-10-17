import SwiftUI

/// Every story the couple shared, newest first, so a story stays after it leaves Home.
/// Opened from the Stories row at the top of Memories.
struct StoriesArchiveView: View {
    let viewModel: StoriesViewModel
    let people: StoryPeople

    @State private var viewer: StoryViewerContent?

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(.storiesArchiveTileAccessibility(
                people.name(of: story),
                story.createdAt.formatted(date: .abbreviated, time: .omitted)
            ))
        )
        .accessibilityAddTraits(.isButton)
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
