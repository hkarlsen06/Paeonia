import SwiftUI

/// The two partners at the top of Home. A ring around an avatar means there is a story
/// from the last day: bright while the partner's is new to you, quiet once you opened it.
/// Your own avatar opens your stories, and a separate button adds one. A thought bubble over an
/// avatar holds that person's note, and your own bubble opens the note editor. Each marker
/// reserves room for its note, decoration and one story action.
struct HomeStoriesStrip: View {
    let viewModel: StoriesViewModel
    let people: StoryPeople
    var avatarSize: CGFloat = 72
    /// Places the two avatars itself, as the map does on Home. Nil lays them out in a row.
    /// Placed avatars leave out the names.
    var arrange: ((_ own: AnyView, _ partner: AnyView) -> AnyView)?
    /// In the row, a view between the two avatars, centered on them, such as the heart.
    /// It overlaps each avatar by `middleOverlap`.
    var middle: AnyView?
    var middleOverlap: CGFloat = 0
    var onMarkerMeasurements: (StoryMarkerMeasurements) -> Void = { _ in }

    @State private var viewer: StoryViewerContent?
    @State private var isComposing = false
    @State private var openNote: OpenNote?
    /// Both avatars on screen, so the note screen can fly them from here.
    @State private var ownAvatarFrame: CGRect = .zero
    @State private var partnerAvatarFrame: CGRect = .zero
    /// The viewer's Add button closes it first, then the composer opens.
    @State private var composesAfterViewer = false
    @State private var isStyling = false
    @State private var ownSize: CGSize = .zero
    @State private var partnerSize: CGSize = .zero
    @State private var ownNoteHeight: CGFloat = 0
    @State private var partnerNoteHeight: CGFloat = 0
    @AccessibilityPresentation(.controls) private var showsControls
    @Environment(\.avatarStyling) private var avatarStyling

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Center to center, wide enough that the two bubbles never touch, and narrow enough
    /// that the partner's bubble stays clear of the streak in the corner.
    private var avatarSpacing: CGFloat { StoryNoteBubble.maxWidth - avatarSize + PaeoniaSpacing.space8 }

    var body: some View {
        // Stories leave Home a day after they were posted, so the rings follow the clock.
        TimelineView(.everyMinute) { context in
            row(now: context.date)
        }
        .onChange(of: markerMeasurements) { _, measurements in
            onMarkerMeasurements(measurements)
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
        .sheet(isPresented: $isStyling) {
            if let avatarStyling {
                NavigationStack {
                    AvatarDecorationPicker(
                        model: avatarStyling, name: people.currentName, photoAssetID: people.currentPhotoAssetID
                    )
                }
            }
        }
        // The note owns its opening. Native cover dismissal does not wait for that animation.
        .fullScreenCover(item: $openNote) { open in
            StoryNoteScreen(
                mode: open.mode,
                viewModel: viewModel,
                people: people,
                sourceFrame: open.sourceFrame
            ) {
                if reduceMotion { withoutAnimation { openNote = nil } } else { openNote = nil }
            }
            .analyticsScreen("story_note")
            .presentationBackground(.clear)
        }
        .preference(key: HomeIsCoveredKey.self, value: viewer != nil || isComposing || openNote != nil || isStyling)
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
                // Map coordinates locate the portrait, independent of controls below it.
                let diameter = avatarSize + 2 * StoryRingAvatar.ringGap
                let alignment = Alignment(horizontal: .center, vertical: .storyAvatarMiddle)
                arrange(
                    AnyView(ownView.frame(height: diameter, alignment: alignment)),
                    AnyView(partnerView.frame(height: diameter, alignment: alignment))
                )
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: PaeoniaSpacing.space24) {
                    ownView
                    partnerView
                }
                .frame(maxWidth: .infinity)
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

    private var markerMeasurements: StoryMarkerMeasurements {
        let diameter = avatarSize + 2 * StoryRingAvatar.ringGap
        var measurements = StoryMarkerMeasurements(size: ownSize, noteHeight: ownNoteHeight, portraitDiameter: diameter)
        measurements.include(StoryMarkerMeasurements(
            size: partnerSize, noteHeight: partnerNoteHeight, portraitDiameter: diameter
        ))
        return measurements
    }
}

extension HomeStoriesStrip {
    private func ownAvatar(_ stories: [Story], note: StoryNote?) -> some View {
        let decoration = avatarStyling?.decorations.own ?? .none
        return VStack(spacing: 0) {
            noteSpace(note?.text, decoration: decoration)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ownNoteHeight = $0 }
            ownAvatarButton(stories)
                .alignmentGuide(.storyAvatarMiddle) { $0[VerticalAlignment.center] }
                .storyNoteBubble(clearance: decoration.noteClearance(photoSize: avatarSize)) {
                    Button {
                        showNote(.edit(current: note), from: ownAvatarFrame)
                    } label: {
                        StoryNoteBubble(text: note?.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(ownNoteLabel(note)))
                }
            addButton
                .padding(.top, actionClearance)
            if arrange == nil, showsControls {
                name(Text(.storiesHomeYourStory))
                    .padding(.top, PaeoniaSpacing.space8)
            }
        }
        .frame(width: markerWidth(decoration))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { ownSize = $0 }
    }

    private func markerWidth(_ decoration: AvatarDecoration) -> CGFloat {
        let width = max(
            StoryNoteBubble.maxWidth, avatarSize + 2 * max(StoryRingAvatar.ringGap, avatarSize * decoration.outset)
        )
        return dynamicTypeSize.isAccessibilitySize ? max(width, avatarSize + 2 * PaeoniaSpacing.space32) : width
    }

    private var actionClearance: CGFloat {
        let decorations = avatarStyling?.decorations ?? CoupleAvatarDecorations()
        let outset = max(decorations.own.bottomOutset, decorations.partner.bottomOutset)
        return max(0, avatarSize * outset - StoryRingAvatar.ringGap) + PaeoniaSpacing.space8
    }

    private func noteSpace(_ text: String?, decoration: AvatarDecoration) -> some View {
        StoryNoteBubble.bodySpace(text: text)
            .padding(.bottom, decoration.noteClearance(photoSize: avatarSize))
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
                ring: stories.isEmpty ? .noStory : .seen,
                size: avatarSize,
                decoration: avatarStyling?.decorations.own ?? .none
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ownAvatarFrame = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(stories.isEmpty ? .storiesHomeAddAccessibility : .storiesHomeYourStory))
        .accessibilityValue(Text((avatarStyling?.decorations.own ?? .none).title))
        .accessibilityIdentifier("stories.own")
        .contextMenu {
            if avatarStyling != nil {
                Button { isStyling = true } label: {
                    Label { Text(.avatarDecorationTitle) } icon: { Image(systemName: "person.crop.circle") }
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            isComposing = true
        } label: {
            Label { Text(.storiesHomeAddButton) } icon: { Image(systemName: "plus") }
                .modifier(StoryBadgeStyle())
                .frame(
                    minWidth: PaeoniaSpacing.compactButtonHeight,
                    minHeight: PaeoniaSpacing.compactButtonHeight,
                    alignment: .top
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.storiesHomeAddAccessibility))
        .accessibilityIdentifier("stories.add")
    }

    private func partnerAvatar(_ stories: [Story], ring: StoryRingState, note: StoryNote?) -> some View {
        let decoration = avatarStyling?.decorations.partner ?? .none
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let note {
                    noteSpace(note.text, decoration: decoration)
                } else {
                    Color.clear.frame(height: decoration.noteClearance(photoSize: avatarSize))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { partnerNoteHeight = $0 }
            partnerAvatarButton(stories, ring: ring, decoration: decoration)
                .storyNoteBubble(clearance: decoration.noteClearance(photoSize: avatarSize)) {
                    if let note {
                        Button {
                            showNote(.read(note), from: partnerAvatarFrame)
                        } label: {
                            StoryNoteBubble(text: note.text)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(.storiesNotePartnerAccessibility(people.partnerName, note.text)))
                    }
                }
            if arrange == nil, showsControls {
                name(Text(people.partnerName))
                    .padding(.top, PaeoniaSpacing.space8)
            }
        }
        .frame(width: markerWidth(decoration))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { partnerSize = $0 }
    }

    /// The partner's portrait and action row form one story button.
    @ViewBuilder
    private func partnerAvatarButton(
        _ stories: [Story], ring: StoryRingState, decoration: AvatarDecoration
    ) -> some View {
        let content = VStack(spacing: 0) {
            StoryRingAvatar(
                mediaAssetID: people.partnerPhotoAssetID,
                name: people.partnerName,
                tint: .paeoniaPartnerTwo,
                ring: ring,
                size: avatarSize,
                decoration: decoration
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { partnerAvatarFrame = $0 }
            .alignmentGuide(.storyAvatarMiddle) { $0[VerticalAlignment.center] }
            StoryStatusBadge(ring: ring == .noStory ? .seen : ring)
                .opacity(ring == .noStory ? 0 : 1)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight, alignment: .top)
                .padding(.top, actionClearance)
        }
        .frame(width: markerWidth(decoration))
        .contentShape(Rectangle())
        if stories.isEmpty {
            content
                .accessibilityLabel(Text(.storiesHomePartnerNoStory(people.partnerName)))
                .accessibilityIdentifier("stories.partner.empty")
        } else {
            Button {
                openPartnerStories(stories)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stories.partner")
            .accessibilityValue(Text(ring == .unseen ? .storiesBadgeNew : .storiesBadgeSeen))
            .accessibilityLabel(Text(
                ring == .unseen
                    ? .storiesHomePartnerNewStory(people.partnerName)
                    : .storiesHomePartnerStory(people.partnerName)
            ))
        }
    }

    private func openPartnerStories(_ stories: [Story]) {
        viewer = StoryViewerContent(stories: stories, startIndex: StoryTimeline.startIndex(in: stories), mode: .home)
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
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
