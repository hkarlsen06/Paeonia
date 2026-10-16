import SwiftUI

/// The two partners at the top of Home. A ring around an avatar means there is a story
/// from the last day: bright while the partner's is new to you, quiet once you opened it.
/// Your own avatar opens your stories, and its plus adds one. A thought bubble over an
/// avatar holds that person's note, and your own bubble opens the note editor.
struct HomeStoriesStrip: View {
    let viewModel: StoriesViewModel
    let people: StoryPeople

    @State private var viewer: StoryViewerContent?
    @State private var isComposing = false
    @State private var editingNote: NoteEdit?
    /// The viewer's Add button closes it first, then the composer opens.
    @State private var composesAfterViewer = false

    private static let avatarSize: CGFloat = 60

    var body: some View {
        // Stories leave Home a day after they were posted, so the rings follow the clock.
        TimelineView(.periodic(from: .now, by: 60)) { context in
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
        }
        .sheet(isPresented: $isComposing) {
            StoryComposerView(viewModel: viewModel, partnerName: people.partnerName)
        }
        .sheet(item: $editingNote) { edit in
            StoryNoteEditor(viewModel: viewModel, partnerName: people.partnerName, current: edit.current)
        }
    }

    /// The note the editor opens with, captured when it opens.
    private struct NoteEdit: Identifiable {
        let id = UUID()
        let current: StoryNote?
    }

    private func row(now: Date) -> some View {
        let own = StoryTimeline.onHome(viewModel.stories, author: people.currentUserID, at: now)
        let partner = StoryTimeline.onHome(viewModel.stories, author: people.partnerUserID, at: now)
        let partnerRing = StoryTimeline.partnerRing(viewModel.stories, partner: people.partnerUserID, at: now)
        let snapshot = StoriesSnapshot(stories: viewModel.stories, notes: viewModel.notes)
        // Bottom alignment keeps the avatars level when only one of them has a bubble.
        return HStack(alignment: .bottom, spacing: PaeoniaSpacing.space20) {
            ownAvatar(own, note: snapshot.note(of: people.currentUserID, at: now))
            partnerAvatar(partner, ring: partnerRing, note: snapshot.note(of: people.partnerUserID, at: now))
            Spacer(minLength: 0)
        }
    }

    private func ownAvatar(_ stories: [Story], note: StoryNote?) -> some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Button {
                editingNote = NoteEdit(current: note)
            } label: {
                StoryNoteBubble(text: note?.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(ownNoteLabel(note)))

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
                    size: Self.avatarSize
                )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) { addButton }
            .accessibilityLabel(Text(stories.isEmpty ? .storiesHomeAddAccessibility : .storiesHomeYourStory))
            .accessibilityAction(named: Text(.storiesHomeAddAccessibility)) { isComposing = true }

            name(Text(.storiesHomeYourStory))
        }
    }

    private var addButton: some View {
        Button {
            isComposing = true
        } label: {
            Image(systemName: "plus")
                .accessibilityHidden(true)
                .font(.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: 22, height: 22)
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

    @ViewBuilder
    private func partnerAvatar(_ stories: [Story], ring: StoryRingState, note: StoryNote?) -> some View {
        let avatar = StoryRingAvatar(
            mediaAssetID: people.partnerPhotoAssetID,
            name: people.partnerName,
            tint: .paeoniaPartnerTwo,
            ring: ring,
            size: Self.avatarSize
        )
        VStack(spacing: PaeoniaSpacing.space4) {
            if let note {
                StoryNoteBubble(text: note.text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(.storiesNotePartnerAccessibility(people.partnerName, note.text)))
            }
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
            name(Text(people.partnerName))
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
            .frame(maxWidth: Self.avatarSize + PaeoniaSpacing.space24)
            .accessibilityHidden(true)
    }

    private func openComposerAfterViewer() {
        guard composesAfterViewer else { return }
        composesAfterViewer = false
        isComposing = true
    }
}
