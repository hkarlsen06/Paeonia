import SwiftUI

/// What a story viewer shows: one person's stories from Home, or the archive in Memories.
struct StoryViewerContent: Identifiable {
    enum Mode {
        /// Stories still on Home. They play on their own and say how long they have left.
        case home
        /// Every story, from Memories. They move only on a tap and show their date.
        case archive
    }

    let id = UUID()
    let stories: [Story]
    let startIndex: Int
    let mode: Mode
}

/// Full-screen stories. A tap on the right goes forward, a tap on the left goes back,
/// and a swipe down closes. Opening the partner's story marks it seen. On your own
/// story you can see whether your partner opened it, add another, or delete it.
struct StoryViewer: View {
    let content: StoryViewerContent
    let people: StoryPeople
    let viewModel: StoriesViewModel
    /// Shown on your own stories from Home. Nil hides the Add button.
    var onAddStory: (() -> Void)?

    @State private var stories: [Story]
    @State private var index: Int
    /// 0 to 1 through the current story on Home.
    @State private var progress: Double = 0
    /// The story whose photo is on screen. The timer waits for it.
    @State private var shownPhotoID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private static let storyDuration: Double = 6
    private static let tick: Double = 0.05

    init(
        content: StoryViewerContent,
        people: StoryPeople,
        viewModel: StoriesViewModel,
        onAddStory: (() -> Void)? = nil
    ) {
        self.content = content
        self.people = people
        self.viewModel = viewModel
        self.onAddStory = onAddStory
        _stories = State(initialValue: content.stories)
        _index = State(initialValue: min(max(content.startIndex, 0), max(content.stories.count - 1, 0)))
    }

    private var story: Story? {
        stories.indices.contains(index) ? stories[index] : nil
    }

    /// The delete question is open or the delete is on its way.
    private var isPaused: Bool {
        isConfirmingDelete || isDeleting
    }

    /// Auto-advance would move on before VoiceOver finishes reading, so it stays off then.
    private var playsOnItsOwn: Bool {
        content.mode == .home && !voiceOverEnabled
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story {
                // The tap zones sit under the photo, which only takes taps on its retry
                // button, so a failed photo can be retried without moving on.
                tapZones(for: story)
                StoryPhotoView(mediaAssetID: story.mediaAssetID) { shownPhotoID = story.id }
                    .id(story.id)
                    .ignoresSafeArea(edges: .bottom)
                overlay(for: story)
            }
        }
        .offset(y: dragOffset)
        .gesture(swipeDownToClose)
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .task(id: TimerKey(storyID: story?.id, photoShown: shownPhotoID == story?.id, isPaused: isPaused)) {
            await runTimer()
        }
        .onChange(of: story?.id, initial: true) { _, _ in
            progress = 0
            if let story { viewModel.markSeen(story) }
        }
        .alert(Text(.storiesViewerDeleteTitle), isPresented: $isConfirmingDelete) {
            Button(role: .cancel) {} label: { Text(.commonCancel) }
            Button(role: .destructive) {
                Task { await deleteCurrent() }
            } label: {
                Text(.storiesViewerDeleteAction)
            }
        } message: {
            Text(.storiesViewerDeleteMessage)
        }
        // The cover hides the app's top banner, so show it here too.
        .paeoniaTopBanner(bannerCenter)
    }

    // MARK: - Layout

    /// The left third goes back, the rest goes forward.
    private func tapZones(for story: Story) -> some View {
        // One VoiceOver element with next and previous actions stands in for the two zones.
        // swiftlint:disable accessibility_trait_for_button
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 0)
                .onTapGesture { goBack() }
            Color.clear
                .contentShape(Rectangle())
                .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 0)
                .onTapGesture { goForward() }
        }
        // swiftlint:enable accessibility_trait_for_button
        .accessibilityElement()
        .accessibilityLabel(Text(.storiesViewerPhotoAccessibility(people.name(of: story))))
        .accessibilityAction(named: Text(.storiesViewerNext)) { goForward() }
        .accessibilityAction(named: Text(.storiesViewerPrevious)) { goBack() }
    }

    private func overlay(for story: Story) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if content.mode == .home {
                StoryProgressBars(count: stories.count, index: index, progress: playsOnItsOwn ? progress : 1)
            }
            StoryViewerHeader(story: story, people: people, mode: content.mode) { dismiss() }
            Spacer(minLength: 0)
            if let caption = story.caption {
                Text(caption)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PaeoniaSpacing.space16)
                    .padding(.vertical, PaeoniaSpacing.space12)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
            }
            if people.isOwn(story) {
                ownFooter(for: story)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.top, PaeoniaSpacing.space8)
        .padding(.bottom, PaeoniaSpacing.space16)
    }

    private func ownFooter(for story: Story) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Label {
                Text(
                    story.seenAt == nil
                        ? .storiesViewerNotSeen(people.partnerName)
                        : .storiesViewerSeen(people.partnerName)
                )
            } icon: {
                Image(systemName: story.seenAt == nil ? "eye.slash" : "eye")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            if let onAddStory, content.mode == .home {
                footerButton(systemImage: "plus", label: .storiesHomeAddAccessibility, action: onAddStory)
            }
            footerButton(systemImage: "trash", label: .storiesViewerDeleteAction) {
                isConfirmingDelete = true
            }
            .disabled(isDeleting)
        }
    }

    private func footerButton(
        systemImage: String,
        label: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var swipeDownToClose: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(PaeoniaMotion.stateChange) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Actions

    private struct TimerKey: Equatable {
        let storyID: UUID?
        let photoShown: Bool
        let isPaused: Bool
    }

    /// Fills the current bar while the photo shows, then moves on. Starts again from
    /// where it was after the delete question closes.
    private func runTimer() async {
        guard playsOnItsOwn, shownPhotoID == story?.id, !isPaused else { return }
        while progress < 1 {
            try? await Task.sleep(for: .seconds(Self.tick))
            guard !Task.isCancelled else { return }
            progress = min(progress + Self.tick / Self.storyDuration, 1)
        }
        goForward()
    }

    private func goForward() {
        if index + 1 < stories.count {
            index += 1
        } else {
            dismiss()
        }
    }

    private func goBack() {
        if index > 0 {
            index -= 1
        } else {
            progress = 0
        }
    }

    private func deleteCurrent() async {
        guard let story, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        guard await viewModel.delete(story) else { return }
        // A tap may have moved on while the delete was sent. Keep showing that story.
        let shownID = self.story?.id
        stories.removeAll { $0.id == story.id }
        if stories.isEmpty {
            dismiss()
        } else if let shownID, shownID != story.id, let shown = stories.firstIndex(where: { $0.id == shownID }) {
            index = shown
        } else {
            index = min(index, stories.count - 1)
        }
    }
}
