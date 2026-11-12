import AppIntents
import SwiftUI

/// The Memories tab: a calm timeline of the couple's saved moments, newest first. Each
/// memory opens its full detail; the toolbar's plus opens the new-memory form. The list
/// is local-first, so cached memories show immediately and the partner's changes
/// arrive live. The tab bar loads the view model, since the Questions tab lists the
/// memory chats too. Recoverable errors route into the shared banner.
struct MemoriesScreen: View {
    let currentUserID: UUID?
    /// The couple's stories, shown as a row that opens the Stories archive. Nil hides it.
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople
    /// Guess my spot's guessed rounds, which "Our places" shows next to the memories.
    let gameRounds: GuessMySpotHistoryViewModel?

    @State private var viewModel: MemoriesViewModel
    @State private var isCreating = false
    @State private var isShowingStories = false
    @State private var isShowingMap = false
    /// iPad landscape: memories sit in a grid of cards instead of one column.
    @State private var isWideLayout = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(
        currentUserID: UUID?,
        viewModel: MemoriesViewModel? = nil,
        stories: StoriesViewModel? = nil,
        storyPeople: StoryPeople = StoryPeople(currentName: "", partnerName: ""),
        gameRounds: GuessMySpotHistoryViewModel? = nil
    ) {
        self.gameRounds = gameRounds
        self.currentUserID = currentUserID
        _viewModel = State(initialValue: viewModel ?? MemoriesViewModel())
        self.stories = stories
        self.storyPeople = storyPeople
    }

    var body: some View {
        content
            .paeoniaTabBackdrop()
            .navigationTitle(Text(.mainTabMemories))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The map is useful from the first memory: with no places yet it lists
                // the memories with "Add place" buttons.
                if !viewModel.timeline.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingMap = true
                        } label: {
                            Image(systemName: "map")
                        }
                        .accessibilityLabel(Text(.memoriesMapOpenAccessibility))
                    }
                }
                if !viewModel.hasLoadedOnce || !viewModel.timeline.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openCreate()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text(.memoriesAddAccessibility))
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingStories) {
                if let stories {
                    StoriesArchiveView(viewModel: stories, people: storyPeople)
                        .analyticsScreen("stories_archive")
                }
            }
            .navigationDestination(isPresented: $isShowingMap) {
                MemoriesMapScreen(viewModel: viewModel, currentUserID: currentUserID, gameRounds: gameRounds)
                    .analyticsScreen("memories_map")
            }
            .navigationDestination(for: UUID.self) { memoryID in
                MemoryDetailView(
                    memoryID: memoryID,
                    currentUserID: currentUserID,
                    viewModel: viewModel
                )
                .analyticsScreen("memory_detail")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { viewModel.flushDraft() }
            }
            // `initial` covers a cold launch, where Siri's request is set before this screen exists.
            .onChange(of: viewModel.isNewMemoryRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                viewModel.isNewMemoryRequested = false
                openCreate()
            }
            .sheet(isPresented: $isCreating, onDismiss: { viewModel.flushDraft() }) {
                NewMemoryEditor(viewModel: viewModel)
            }
            // New-memory alerts are seen once their memory is on the timeline.
            .task(id: shownMemoryIDs) {
                await DeliveredNotifications.clearMemories(shownMemoryIDs: shownMemoryIDs)
            }
            .onChange(of: viewModel.notice) { _, notice in
                showBanner(for: notice)
            }
    }

    private var shownMemoryIDs: Set<UUID> {
        Set(viewModel.timeline.flatMap(\.memories).map(\.snapshot.memoryID))
    }

    private var content: some View {
        ZStack {
            if !viewModel.hasLoadedOnce, let failure = viewModel.loadFailure {
                PaeoniaLoadFailureView(failure: failure, offlineMessage: .commonLoadFailedMessage) {
                    Button { Task { await viewModel.load() } } label: { Text(.commonTryAgain) }
                        .buttonStyle(PaeoniaSecondaryButtonStyle())
                }
            } else if !viewModel.hasLoadedOnce {
                ProgressView()
            } else if viewModel.timeline.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
        // The blank first-load surface dissolves into the timeline (or empty state),
        // and saving the first memory / deleting the last one crossfades between the
        // two instead of swapping in one frame. Fades only, so Reduce Motion needs
        // no branch.
        .animation(PaeoniaMotion.stateChange, value: viewModel.hasLoadedOnce)
        .animation(PaeoniaMotion.stateChange, value: viewModel.timeline.isEmpty)
    }

    /// Newest first, in month sections. The headers scroll with the cards: a pinned header
    /// would need an opaque strip, which shows as a dark band over the tabs' light, and
    /// every card shows its own date anyway. A wide iPad shows one grid of cards instead.
    /// The Stories row, once the couple has shared a story.
    @ViewBuilder
    private var storiesRow: some View {
        if let stories, !stories.stories.isEmpty {
            MemoriesStoriesRow(stories: stories.stories) { isShowingStories = true }
        }
    }

    private var timeline: some View {
        ScrollView {
            storiesRow
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .paeoniaReadableWidth(
                    isWideLayout ? PaeoniaSpacing.wideContentWidth : PaeoniaSpacing.readableContentWidth
                )
            LazyVGrid(
                columns: timelineColumns,
                alignment: .leading,
                spacing: PaeoniaSpacing.space16
            ) {
                if isWideLayout {
                    // Most months hold only a memory or two, so month sections would
                    // leave most of each grid row empty. Every card shows its own date.
                    memoryLinks(months.flatMap(\.memories))
                } else {
                    ForEach(months) { month in
                        Section {
                            memoryLinks(month.memories)
                        } header: {
                            monthHeader(month)
                        }
                    }
                }
            }
            // A newly saved memory glides into place (and a deleted one closes up)
            // rather than reflowing the feed in a single frame.
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: memoryIDs)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            // The month headers carry their own top padding, and the wide grid has none.
            .padding(.top, isWideLayout ? PaeoniaSpacing.space16 : 0)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth(
                isWideLayout ? PaeoniaSpacing.wideContentWidth : PaeoniaSpacing.readableContentWidth
            )
        }
        .paeoniaWideLayout($isWideLayout)
        .refreshable { await viewModel.refresh() }
    }

    private func memoryLinks(_ records: [MemoryRecord]) -> some View {
        ForEach(records, id: \.snapshot.memoryID) { record in
            NavigationLink(value: record.snapshot.memoryID) {
                MemoryCardView(record: record)
            }
            .buttonStyle(.plain)
            // Siri can tell which memory "this one" is from what is on screen.
            .appEntityIdentifier(EntityIdentifier(for: MemoryAlbumEntity.self, identifier: record.snapshot.memoryID))
        }
    }

    private var timelineColumns: [GridItem] {
        if isWideLayout {
            [GridItem(.adaptive(minimum: 340), spacing: PaeoniaSpacing.space16, alignment: .top)]
        } else {
            [GridItem(.flexible())]
        }
    }

    private func monthHeader(_ month: MemoryTimelineMonth) -> some View {
        Text(month.monthStartUTC, format: MemoryDateStyle.month)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space4)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        ScrollView {
            storiesRow
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .paeoniaReadableWidth()
            PaeoniaEmptyStateView(
                title: .memoriesEmptyTitle,
                illustration: .memoriesPhotoStack
            ) {
                Button {
                    openCreate()
                } label: {
                    Text(.memoriesEmptyAction)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .frame(maxWidth: 280)
                .padding(.top, PaeoniaSpacing.space8)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .refreshable { await viewModel.refresh() }
    }

    /// The day and within-day order comes from `MemoryTimeline.grouped`; each card
    /// carries its own date, so sections are per month rather than per day.
    private var months: [MemoryTimelineMonth] {
        MemoryTimeline.months(viewModel.timeline)
    }

    private var memoryIDs: [UUID] {
        viewModel.timeline.flatMap { $0.memories.map(\.snapshot.memoryID) }
    }

    /// Opens the new-memory form. A fresh (empty) draft defaults its date to today;
    /// a draft left over from an earlier dismissal is restored untouched.
    private func openCreate() {
        var draft = viewModel.draft
        if draft.isEmpty { draft.date = Date() }
        draft.visitID = nil
        if draft != viewModel.draft { viewModel.updateDraft(draft) }
        isCreating = true
    }

    private func showBanner(for notice: MemoriesNotice?) {
        guard let notice else { return }
        bannerCenter.show(notice.banner)
        viewModel.dismissNotice()
    }
}
