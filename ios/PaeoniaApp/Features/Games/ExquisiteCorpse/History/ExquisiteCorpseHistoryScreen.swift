import SwiftUI

/// "Our creatures": a count above a grid of every finished creature, with an
/// "All" and a "Starred" filter. A cell opens the creature.
struct ExquisiteCorpseHistoryScreen: View {
    @Bindable var viewModel: ExquisiteCorpseHistoryViewModel

    /// Three columns on a phone, more where there is room.
    private static let columnMinimum: CGFloat = 104

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                header
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
        .navigationTitle(Text(.exquisiteCorpseHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Runs again when the filter changes, and when the screen comes back from a creature.
        .task(id: viewModel.filter) { await viewModel.refresh() }
        .accessibilityIdentifier("corpse.history")
    }

    /// "12 creatures". Nothing until the list has loaded.
    @ViewBuilder
    private var header: some View {
        if viewModel.creatureCount > 0 {
            Text(.exquisiteCorpseHistoryCount(viewModel.creatureCount))
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("corpse.history.count")
        }
    }

    private var filterPicker: some View {
        Picker(selection: $viewModel.filter) {
            Text(.gamesDrawAndGuessHistoryFilterAll).tag(ExquisiteCorpseHistoryViewModel.Filter.all)
            Text(.gamesDrawAndGuessHistoryFilterStarred).tag(ExquisiteCorpseHistoryViewModel.Filter.starred)
        } label: {
            Text(.gamesDrawAndGuessHistoryFilterLabel)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("corpse.history.filter")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, minHeight: 160)
        case .offline:
            offlineState
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
                spacing: PaeoniaSpacing.space16
            ) {
                ForEach(viewModel.visibleFigures) { figure in
                    NavigationLink(value: GamesDestination.exquisiteCorpseHistoryDetail(figure.id)) {
                        ExquisiteCorpseHistoryCell(
                            figure: figure,
                            partnerName: viewModel.partnerName,
                            isStarred: viewModel.stars.isStarred(figure.id),
                            drawings: viewModel.drawings
                        )
                    }
                    .buttonStyle(.plain)
                    .task { await viewModel.loadMoreIfNeeded(after: figure) }
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
            Text(.exquisiteCorpseHistoryLoadMoreFailed)
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
        if viewModel.filter == .starred, !viewModel.hasNoCreatures {
            PaeoniaEmptyStateView(
                title: .exquisiteCorpseHistoryEmptyStarredTitle,
                message: .exquisiteCorpseHistoryEmptyStarredMessage,
                systemImage: "star"
            )
        } else {
            PaeoniaEmptyStateView(
                title: .exquisiteCorpseHistoryEmptyTitle,
                message: .exquisiteCorpseHistoryEmptyMessage,
                systemImage: "square.grid.2x2"
            )
        }
    }

    private var offlineState: some View {
        PaeoniaEmptyStateView(
            title: .gamesDrawAndGuessChooseOfflineTitle,
            message: .exquisiteCorpseHistoryOfflineMessage,
            systemImage: "wifi.slash"
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
