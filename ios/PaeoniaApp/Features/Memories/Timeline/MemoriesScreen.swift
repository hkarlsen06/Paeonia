import SwiftUI

/// The Memories tab: a calm timeline of the couple's saved moments, newest first. Each
/// memory opens its full detail; the toolbar's plus opens the new-memory form. The list
/// is local-first, so cached memories show immediately and the partner's changes
/// arrive live. Recoverable errors route into the shared top banner.
struct MemoriesScreen: View {
    let currentUserID: UUID?
    let coupleID: UUID?
    /// Flushes pending local memory writes to the backend (wired to the app's sync
    /// engine by the host). Called after each local change and on pull-to-refresh.
    let onLocalChange: @MainActor @Sendable () async -> Void
    /// The couple's stories, shown as a row that opens the Stories archive. Nil hides it.
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople

    @State private var viewModel: MemoriesViewModel
    @State private var isCreating = false
    @State private var isShowingStories = false
    /// iPad landscape: memories sit in a grid of cards instead of one column.
    @State private var isWideLayout = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(
        currentUserID: UUID?,
        coupleID: UUID?,
        viewModel: MemoriesViewModel? = nil,
        stories: StoriesViewModel? = nil,
        storyPeople: StoryPeople = StoryPeople(currentName: "", partnerName: ""),
        onLocalChange: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
        _viewModel = State(initialValue: viewModel ?? MemoriesViewModel())
        self.stories = stories
        self.storyPeople = storyPeople
        self.onLocalChange = onLocalChange
    }

    var body: some View {
        content
            .paeoniaTabBackdrop()
            .navigationTitle(Text(.mainTabMemories))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openCreate()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text(.memoriesAddAccessibility))
                }
            }
            .navigationDestination(isPresented: $isShowingStories) {
                if let stories {
                    StoriesArchiveView(viewModel: stories, people: storyPeople)
                        .analyticsScreen("stories_archive")
                }
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
            .sheet(isPresented: $isCreating, onDismiss: { viewModel.flushDraft() }) {
                // The view model keeps the draft and saves it on the device, so a swipe-down
                // or a route change never throws away a half-written memory. A successful
                // save or a deliberate Cancel clears it.
                MemoryEditorView(
                    draft: draftBinding,
                    allowsPhotos: viewModel.canAttachPhotos,
                    uploadProgress: viewModel.photoUploadProgress
                ) { title, date, note, photos, _ in
                    await viewModel.createMemory(title: title, date: date, note: note, photos: photos)
                }
            }
            .task(id: currentUserID) {
                viewModel.setLocalChangeSyncHandler(onLocalChange)
                await viewModel.configure(currentUserID: currentUserID, coupleID: coupleID)
            }
            .task(id: currentUserID) {
                await viewModel.observeStoreChanges()
            }
            // New-memory alerts are seen once their memory is on the timeline.
            .task(id: shownMemoryIDs) {
                await DeliveredNotifications.clearMemories(shownMemoryIDs: shownMemoryIDs)
            }
            .onChange(of: coupleID) { _, newCoupleID in
                viewModel.updateContext(coupleID: newCoupleID)
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
            if !viewModel.hasLoadedOnce {
                // Blank surface for the split second before the local cache resolves, so the
                // empty state never flashes before we know whether there are memories.
                Color.clear
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
                message: .memoriesEmptyMessage,
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
        if viewModel.draft.isEmpty {
            var fresh = viewModel.draft
            fresh.date = Date()
            viewModel.updateDraft(fresh)
        }
        isCreating = true
    }

    private var draftBinding: Binding<MemoryDraft> {
        Binding(get: { viewModel.draft }, set: { viewModel.updateDraft($0) })
    }

    private func showBanner(for notice: MemoriesNotice?) {
        guard let notice else { return }
        bannerCenter.show(notice.banner)
        viewModel.dismissNotice()
    }
}
