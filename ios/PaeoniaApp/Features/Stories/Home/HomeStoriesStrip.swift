import SwiftUI

/// The two partners at the top of Home. A ring around an avatar means there is a story
/// from the last day: bright while the partner's is new to you, quiet once you opened it.
/// Your own avatar opens your stories, and its plus adds one. A thought bubble over an
/// avatar holds that person's note, and your own bubble opens the note editor. The row's
/// top is the top of a full two-line bubble, so the header can line it up with the streak.
struct HomeStoriesStrip: View {
    let viewModel: StoriesViewModel
    let people: StoryPeople
    var avatarSize: CGFloat = 72
    /// Places the two avatars itself, as the map does on Home. Nil lays them out in a row.
    /// Placed avatars leave out the reserved bubble room and the names.
    var arrange: ((_ own: AnyView, _ partner: AnyView) -> AnyView)?
    /// In the row, a view between the two avatars, centered on them, such as the heart.
    /// It overlaps each avatar by `middleOverlap`.
    var middle: AnyView?
    var middleOverlap: CGFloat = 0

    @State private var viewer: StoryViewerContent?
    @State private var isComposing = false
    @State private var openNote: OpenNote?
    /// Both avatars on screen, so the note screen can fly them from here.
    @State private var ownAvatarFrame: CGRect = .zero
    @State private var partnerAvatarFrame: CGRect = .zero
    /// The viewer's Add button closes it first, then the composer opens.
    @State private var composesAfterViewer = false

    /// The plus on your avatar that adds a story.
    private static let plusBadgeSize: CGFloat = 22
    /// Center to center, wide enough that the two bubbles never touch, and narrow enough
    /// that the partner's bubble stays clear of the streak in the corner.
    private var avatarSpacing: CGFloat { StoryNoteBubble.maxWidth - avatarSize + PaeoniaSpacing.space8 }

    var body: some View {
        // Stories leave Home a day after they were posted, so the rings follow the clock.
        TimelineView(.everyMinute) { context in
            row(now: context.date)
        }
        .fullScreenCover(item: $viewer, onDismiss: openComposerAfterViewer) { content in
            StoryViewer(
                content: content,
                people: people,
                viewModel: viewModel,
                onAddStory: {
                    composesAfterViewer = true
                    viewer = nil
                }
            )
            .analyticsScreen("story_viewer")
        }
        // A story push opens its story. The deep link reads the stories before it asks.
        .onChange(of: viewModel.openRequest, initial: true) { _, request in
            openRequestedStory(request)
        }
        // The "Post a story" row on Home's things to try.
        .onChange(of: viewModel.isComposerRequested, initial: true) { _, isRequested in
            guard isRequested else { return }
            viewModel.consumeComposerRequest()
            isComposing = true
        }
        .sheet(isPresented: $isComposing) {
            StoryComposerView(viewModel: viewModel, partnerName: people.partnerName)
                .analyticsScreen("story_composer")
        }
        // The note screen runs its own opening and closing, flying the avatar between
        // Home and the middle of the screen, so the cover appears and leaves without animation.
        .fullScreenCover(item: $openNote) { open in
            StoryNoteScreen(
                mode: open.mode,
                viewModel: viewModel,
                people: people,
                sourceFrame: open.sourceFrame
            ) {
                withoutAnimation { openNote = nil }
            }
            .analyticsScreen("story_note")
            .presentationBackground(.clear)
        }
    }

    /// Opens the story a push named. A story that left Home opens alone in the archive style.
    /// A story that is gone ends the request without opening anything.
    private func openRequestedStory(_ request: StoryOpenRequest?) {
        guard let request else { return }
        defer { viewModel.consumeOpenRequest() }
        guard let story = viewModel.stories.first(where: { $0.id == request.storyID }) else { return }
        let onHome = StoryTimeline.onHome(viewModel.stories, author: story.authorUserID, at: Date())
        if let index = onHome.firstIndex(where: { $0.id == story.id }) {
            viewer = StoryViewerContent(
                stories: onHome, startIndex: index, mode: .home, showsReplies: request.showsReplies
            )
        } else {
            viewer = StoryViewerContent(
                stories: [story], startIndex: 0, mode: .archive, showsReplies: request.showsReplies
            )
        }
    }

    /// The note screen's mode and where the avatar was, captured when it opens.
    private struct OpenNote: Identifiable {
        let id = UUID()
        let mode: StoryNoteScreen.Mode
        let sourceFrame: CGRect
    }

    private func showNote(_ mode: StoryNoteScreen.Mode, from sourceFrame: CGRect) {
        let open = OpenNote(mode: mode, sourceFrame: sourceFrame)
        withoutAnimation { openNote = open }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func row(now: Date) -> some View {
        let own = StoryTimeline.onHome(viewModel.stories, author: people.currentUserID, at: now)
        let partner = StoryTimeline.onHome(viewModel.stories, author: people.partnerUserID, at: now)
        let partnerRing = StoryTimeline.partnerRing(viewModel.stories, partner: people.partnerUserID, at: now)
        let snapshot = StoriesSnapshot(stories: viewModel.stories, notes: viewModel.notes)
        let ownView = ownAvatar(own, note: snapshot.note(of: people.currentUserID, at: now))
        let partnerView = partnerAvatar(
            partner, ring: partnerRing, note: snapshot.note(of: people.partnerUserID, at: now)
        )
        return Group {
            if let arrange {
                arrange(AnyView(ownView), AnyView(partnerView))
            } else {
                HStack(alignment: .storyAvatarMiddle, spacing: middle == nil ? avatarSpacing : -middleOverlap) {
                    ownView
                    if let middle {
                        middle
                    }
                    partnerView
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func ownAvatar(_ stories: [Story], note: StoryNote?) -> some View {
        VStack(spacing: 0) {
            // Room for the tallest note above the avatar, so the row's top is the top of
            // a full bubble, whoever has a note.
            if arrange == nil {
                StoryNoteBubble.tallestBody
            }
            ownAvatarButton(stories)
                .alignmentGuide(.storyAvatarMiddle) { $0[VerticalAlignment.center] }
                .overlay(alignment: .bottomTrailing) { addButton }
                .accessibilityLabel(Text(stories.isEmpty ? .storiesHomeAddAccessibility : .storiesHomeYourStory))
                .accessibilityAction(named: Text(.storiesHomeAddAccessibility)) { isComposing = true }
                .storyNoteBubble {
                    Button {
                        showNote(.edit(current: note), from: ownAvatarFrame)
                    } label: {
                        StoryNoteBubble(text: note?.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(ownNoteLabel(note)))
                }

            if arrange == nil {
                name(Text(.storiesHomeYourStory))
                    .padding(.top, PaeoniaSpacing.space4)
            }
        }
    }

    /// Opens your stories, or the composer when you have none.
    private func ownAvatarButton(_ stories: [Story]) -> some View {
        Button {
            if stories.isEmpty {
                isComposing = true
            } else {
                viewer = StoryViewerContent(stories: stories, startIndex: 0, mode: .home)
            }
        } label: {
            StoryRingAvatar(
                mediaAssetID: people.currentPhotoAssetID,
                name: people.currentName,
                tint: .paeoniaPartnerOne,
                ring: stories.isEmpty ? .noStory : .unseen,
                size: avatarSize
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ownAvatarFrame = $0 }
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            isComposing = true
        } label: {
            Image(systemName: "plus")
                .accessibilityHidden(true)
                .font(.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: Self.plusBadgeSize, height: Self.plusBadgeSize)
                .background(Circle().fill(.paeoniaAccentPrimary))
                .overlay(Circle().strokeBorder(.paeoniaBackgroundPrimary, lineWidth: 2))
                // A bigger target than the badge looks.
                .padding(PaeoniaSpacing.space8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: PaeoniaSpacing.space8, y: PaeoniaSpacing.space8)
        // The avatar's own action covers it for VoiceOver.
        .accessibilityHidden(true)
    }

    private func partnerAvatar(_ stories: [Story], ring: StoryRingState, note: StoryNote?) -> some View {
        VStack(spacing: 0) {
            // Room for the tallest note above the avatar, so the row's top is the top of
            // a full bubble, whoever has a note.
            if arrange == nil {
                StoryNoteBubble.tallestBody
            }
            partnerAvatarButton(stories, ring: ring)
                .alignmentGuide(.storyAvatarMiddle) { $0[VerticalAlignment.center] }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { partnerAvatarFrame = $0 }
                .storyNoteBubble {
                    if let note {
                        // Opens the whole note, which may be longer than the bubble shows.
                        Button {
                            showNote(.read(note), from: partnerAvatarFrame)
                        } label: {
                            StoryNoteBubble(text: note.text)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(.storiesNotePartnerAccessibility(people.partnerName, note.text)))
                    }
                }
            if arrange == nil {
                name(Text(people.partnerName))
                    .padding(.top, PaeoniaSpacing.space4)
            }
        }
    }

    /// Opens the partner's stories. Without any, it is only the avatar.
    @ViewBuilder
    private func partnerAvatarButton(_ stories: [Story], ring: StoryRingState) -> some View {
        let avatar = StoryRingAvatar(
            mediaAssetID: people.partnerPhotoAssetID,
            name: people.partnerName,
            tint: .paeoniaPartnerTwo,
            ring: ring,
            size: avatarSize
        )
        if stories.isEmpty {
            avatar
                .accessibilityLabel(Text(.storiesHomePartnerNoStory(people.partnerName)))
        } else {
            Button {
                viewer = StoryViewerContent(
                    stories: stories,
                    startIndex: StoryTimeline.startIndex(in: stories),
                    mode: .home
                )
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    ring == .unseen
                        ? .storiesHomePartnerNewStory(people.partnerName)
                        : .storiesHomePartnerStory(people.partnerName)
                )
            )
        }
    }

    private func ownNoteLabel(_ note: StoryNote?) -> LocalizedStringResource {
        if let note {
            .storiesNoteOwnAccessibility(note.text)
        } else {
            .storiesNoteAddAccessibility
        }
    }

    private func name(_ text: Text) -> some View {
        text
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .lineLimit(1)
            .frame(maxWidth: avatarSize + PaeoniaSpacing.space24)
            .accessibilityHidden(true)
    }

    private func openComposerAfterViewer() {
        guard composesAfterViewer else { return }
        composesAfterViewer = false
        isComposing = true
    }
}

extension VerticalAlignment {
    private enum StoryAvatarMiddle: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    /// The middle of the avatars in the stories row, below the room kept for note bubbles.
    static let storyAvatarMiddle = VerticalAlignment(StoryAvatarMiddle.self)
}
