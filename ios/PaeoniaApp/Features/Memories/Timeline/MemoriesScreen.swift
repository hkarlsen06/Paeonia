import SwiftUI

/// The Memories tab: a calm timeline of the couple's saved moments, newest first. Each
/// memory opens its full detail; the toolbar's plus opens the new-memory form. The list
/// is local-first, so cached memories show immediately and a background pull refreshes
/// them. Recoverable errors route into the shared top banner.
struct MemoriesScreen: View {
    let currentUserID: UUID?
    let coupleID: UUID?
    /// Flushes pending local memory writes to the backend (wired to the app's sync
    /// engine by the host). Called after each local change and on pull-to-refresh.
    let onLocalChange: @MainActor @Sendable () async -> Void

    @State private var viewModel = MemoriesViewModel()
    @State private var isCreating = false
    /// The in-progress new-memory form, held here rather than inside the sheet so an
    /// accidental swipe-to-dismiss never throws away a half-written memory. Reopening
    /// the form restores it; a successful save (or a deliberate Cancel) clears it.
    @State private var draft = MemoryDraft()
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(
        currentUserID: UUID?,
        coupleID: UUID?,
        onLocalChange: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.currentUserID = currentUserID
        self.coupleID = coupleID
        self.onLocalChange = onLocalChange
    }

    var body: some View {
        content
            .background(.paeoniaBackgroundPrimary)
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
            .navigationDestination(for: UUID.self) { memoryID in
                MemoryDetailView(
                    memoryID: memoryID,
                    currentUserID: currentUserID,
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $isCreating) {
                MemoryEditorView(draft: $draft, allowsPhotos: viewModel.canAttachPhotos) { title, date, note, photos, _ in
                    let saved = await viewModel.createMemory(title: title, date: date, note: note, photos: photos)
                    if saved {
                        draft = MemoryDraft()
                    }
                    return saved
                }
            }
            .task(id: currentUserID) {
                viewModel.setLocalChangeSyncHandler(onLocalChange)
                await viewModel.configure(currentUserID: currentUserID, coupleID: coupleID)
            }
            .onChange(of: coupleID) { _, newCoupleID in
                viewModel.updateContext(coupleID: newCoupleID)
            }
            .onChange(of: viewModel.notice) { _, notice in
                showBanner(for: notice)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoadedOnce {
            // Blank surface for the split second before the local cache resolves, so the
            // empty state never flashes before we know whether there are memories.
            Color.paeoniaBackgroundPrimary
        } else if memories.isEmpty {
            emptyState
        } else {
            timeline
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: PaeoniaSpacing.space16) {
                ForEach(memories, id: \.snapshot.memoryID) { record in
                    NavigationLink(value: record.snapshot.memoryID) {
                        MemoryCardView(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
        }
        .refreshable { await viewModel.refresh() }
    }

    private var emptyState: some View {
        ScrollView {
            PaeoniaEmptyStateView(
                title: .memoriesEmptyTitle,
                message: .memoriesEmptyMessage,
                systemImage: "memories"
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

    /// The timeline flattened into a single newest-first feed. The day/within-day order
    /// comes from `MemoryTimeline.grouped`; each card carries its own date, so the feed
    /// stays clean without per-day dividers.
    private var memories: [MemoryRecord] {
        viewModel.timeline.flatMap(\.memories)
    }

    /// Opens the new-memory form. A fresh (empty) draft defaults its date to today;
    /// a draft left over from an earlier dismissal is restored untouched.
    private func openCreate() {
        if draft.isEmpty {
            draft.date = Date()
        }
        isCreating = true
    }

    private func showBanner(for notice: MemoriesViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        viewModel.dismissNotice()
    }
}
