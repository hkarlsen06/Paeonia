import SwiftUI

/// "Our stories": every finished story, newest first, with an "All" and a
/// "Starred" filter. A row opens the story.
struct StoryChainHistoryScreen: View {
    @Bindable var viewModel: StoryChainHistoryViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                filterPicker
                content
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await viewModel.refresh() }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.storyChainHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Runs again when the filter changes, and when the screen comes back from a story.
        .task(id: viewModel.filter) { await viewModel.refresh() }
        .onChange(of: viewModel.stars.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.stars.clearNotice()
        }
        .accessibilityIdentifier("storyChain.history")
    }

    private var filterPicker: some View {
        Picker(selection: $viewModel.filter) {
            Text(.storyChainHistoryFilterAll).tag(StoryChainHistoryViewModel.Filter.all)
            Text(.storyChainHistoryFilterStarred).tag(StoryChainHistoryViewModel.Filter.starred)
        } label: {
            Text(.storyChainHistoryFilterLabel)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("storyChain.history.filter")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let failure):
            failureState(failure)
        case .loaded:
            if viewModel.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var list: some View {
        LazyVStack(spacing: PaeoniaSpacing.space12) {
            ForEach(viewModel.visibleItems) { item in
                NavigationLink(value: GamesDestination.storyChainHistoryDetail(item.id)) {
                    StoryChainHistoryRow(item: item, isStarred: viewModel.stars.isStarred(item.id))
                }
                .buttonStyle(.plain)
                .task { await viewModel.loadMoreIfNeeded(after: item) }
            }
            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity)
            }
            if viewModel.loadMoreFailed {
                loadMoreFailedRow
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: viewModel.visibleItems.map(\.id))
    }

    /// The last row's own load runs once, so this button is the way to try again.
    private var loadMoreFailedRow: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.storyChainHistoryLoadMoreFailed)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.retryLoadMore() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.filter == .starred, !viewModel.hasNoStories {
            PaeoniaEmptyStateView(
                title: .storyChainHistoryEmptyStarredTitle,
                message: .storyChainHistoryEmptyStarredMessage,
                systemImage: "star"
            )
        } else {
            PaeoniaEmptyStateView(
                title: .storyChainHistoryEmptyTitle,
                message: .storyChainHistoryEmptyMessage,
                systemImage: "books.vertical"
            )
        }
    }

    private func failureState(_ failure: PaeoniaFailure) -> some View {
        PaeoniaLoadFailureView(
            failure: failure,
            offlineTitle: .storyChainOfflineTitle,
            offlineMessage: .storyChainHistoryOfflineMessage,
            failedMessage: .storyChainHistoryFailedMessage
        ) {
            Button {
                Task { await viewModel.retry() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        }
    }
}
