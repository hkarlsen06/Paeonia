import SwiftUI

/// "Our drawings": the records of both partners above a grid of every finished
/// drawing, with an "All" and a "Starred" filter. A cell opens the drawing.
struct DrawAndGuessHistoryScreen: View {
    @Bindable var viewModel: DrawAndGuessHistoryViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// Two columns on a phone, more where there is room.
    private static let columnMinimum: CGFloat = 160

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                DrawAndGuessRecordsView(
                    me: viewModel.me,
                    partner: viewModel.partner,
                    mine: viewModel.myRecords,
                    theirs: viewModel.partnerRecords
                )
                .frame(maxWidth: PaeoniaSpacing.readableContentWidth, alignment: .leading)

                filterPicker
                    .frame(maxWidth: PaeoniaSpacing.readableContentWidth)

                content
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth(PaeoniaSpacing.wideContentWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await viewModel.refresh() }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.gamesDrawAndGuessHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Runs again when the filter changes, and when the screen comes back from a drawing.
        .task(id: viewModel.filter) { await viewModel.refresh() }
        .onChange(of: viewModel.stars.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.stars.clearNotice()
        }
        .accessibilityIdentifier("draw.history")
    }

    private var filterPicker: some View {
        Picker(selection: $viewModel.filter) {
            Text(.gamesDrawAndGuessHistoryFilterAll).tag(DrawAndGuessHistoryViewModel.Filter.all)
            Text(.gamesDrawAndGuessHistoryFilterStarred).tag(DrawAndGuessHistoryViewModel.Filter.starred)
        } label: {
            Text(.gamesDrawAndGuessHistoryFilterLabel)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("draw.history.filter")
    }

    // MARK: - Content

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
                grid
            }
        }
    }

    private var grid: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: Self.columnMinimum), spacing: PaeoniaSpacing.space12, alignment: .top),
                ],
                spacing: PaeoniaSpacing.space12
            ) {
                ForEach(viewModel.visibleRounds) { round in
                    NavigationLink(value: GamesDestination.drawAndGuessHistoryDetail(round.id)) {
                        DrawAndGuessHistoryCell(
                            round: round,
                            drawerName: viewModel.drawerName(of: round),
                            isStarred: viewModel.stars.isStarred(round.id),
                            drawings: viewModel.drawings
                        )
                    }
                    .buttonStyle(.plain)
                    .task { await viewModel.loadMoreIfNeeded(after: round) }
                }
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
    }

    /// The last cell's own load runs once, so this button is the way to try again.
    private var loadMoreFailedRow: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.gamesDrawAndGuessHistoryLoadMoreFailed)
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
        if viewModel.filter == .starred, !viewModel.hasNoDrawings {
            PaeoniaEmptyStateView(
                title: .gamesDrawAndGuessHistoryEmptyStarredTitle,
                message: .gamesDrawAndGuessHistoryEmptyStarredMessage,
                systemImage: "star"
            )
        } else {
            PaeoniaEmptyStateView(
                title: .gamesDrawAndGuessHistoryEmptyTitle,
                message: .gamesDrawAndGuessHistoryEmptyMessage,
                systemImage: "square.grid.2x2"
            )
        }
    }

    private func failureState(_ failure: PaeoniaFailure) -> some View {
        PaeoniaLoadFailureView(
            failure: failure,
            offlineTitle: .gamesDrawAndGuessChooseOfflineTitle,
            offlineMessage: .gamesDrawAndGuessHistoryOfflineMessage,
            failedMessage: .gamesDrawAndGuessHistoryFailedMessage
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
