import SwiftUI

/// "Our melds": the couple's records above a list of every finished game, newest
/// first. A row opens the trail of that game.
struct MindMeldHistoryScreen: View {
    let viewModel: MindMeldHistoryViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                records
                content
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await viewModel.load() }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.mindMeldHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Runs again when the screen comes back from a game.
        .task { await viewModel.load() }
        .accessibilityIdentifier("mindMeld.history")
    }

    // MARK: Records

    @ViewBuilder
    private var records: some View {
        if let stats = viewModel.stats {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space16))
            layout {
                record(.mindMeldHistoryRecordsMelds, value: stats.melds.formatted())
                record(.mindMeldHistoryRecordsFewest, value: stats.fewestRounds?.formatted())
            }
            .accessibilityIdentifier("mindMeld.history.records")
        }
    }

    /// A caption and a big number, or "Not yet" when there is no number.
    private func record(_ label: LocalizedStringResource, value: String?) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(label)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            if let value {
                Text(value)
                    .font(PaeoniaTypography.countdownNumber)
                    .monospacedDigit()
                    .foregroundStyle(.paeoniaTextPrimary)
            } else {
                Text(.mindMeldHistoryRecordsNone)
                    .font(PaeoniaTypography.countdownNumber)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.games.isEmpty {
            list
        } else if viewModel.isLoading {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if viewModel.loadFailed {
            offlineState
        } else {
            PaeoniaEmptyStateView(
                title: .mindMeldHistoryEmptyTitle,
                message: .mindMeldHistoryEmptyMessage,
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        }
    }

    private var list: some View {
        LazyVStack(spacing: PaeoniaSpacing.space12) {
            ForEach(viewModel.games) { game in
                NavigationLink(value: GamesDestination.mindMeldHistoryDetail(game.id)) {
                    MindMeldHistoryRow(game: game)
                }
                .buttonStyle(.plain)
                .task { await viewModel.loadMoreIfNeeded(after: game) }
            }
            if viewModel.loadMoreFailed {
                loadMoreFailedRow
            } else if viewModel.hasMore {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The last row's own load runs once, so this button is the way to try again.
    private var loadMoreFailedRow: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.mindMeldHistoryLoadMoreFailed)
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
            .accessibilityIdentifier("mindMeld.history.retryMore")
        }
        .frame(maxWidth: .infinity)
    }

    private var offlineState: some View {
        PaeoniaEmptyStateView(
            title: .mindMeldOfflineTitle,
            message: .mindMeldHistoryOfflineMessage,
            systemImage: "wifi.slash"
        ) {
            Button {
                Task { await viewModel.load() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
            .accessibilityIdentifier("mindMeld.history.retry")
        }
    }
}

// MARK: - Row

/// One finished game: the word the couple met on, or how it ended, and under it
/// the number of rounds and the date.
private struct MindMeldHistoryRow: View {
    let game: RemoteMindMeldHistoryGame

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                title
                Text(verbatim: game.roundsAndDate)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            Spacer(minLength: PaeoniaSpacing.space8)
            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mindMeld.history.row")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
    }

    @ViewBuilder
    private var title: some View {
        switch game.ending {
        case let .melded(word):
            HStack(spacing: PaeoniaSpacing.space8) {
                MindMeldPetalMark()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.paeoniaSuccess)
                Text(verbatim: word.localizedUppercase)
                    .font(PaeoniaTypography.title)
                    .tracking(0.6)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(2)
            }
        case .gotAway:
            Text(.mindMeldHistoryRowGotAway)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextSecondary)
        case .startedOver:
            Text(.mindMeldHistoryRowStartedOver)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }
}

// MARK: - Reading a game

extension RemoteMindMeldHistoryGame {
    nonisolated enum Ending: Equatable {
        /// The couple met on this word. It is the last round's word, mine.
        case melded(word: String)
        case gotAway
        case startedOver
    }

    var ending: Ending {
        switch state {
        case .melded: .melded(word: rounds.last?.myWord ?? "")
        case .ended where endReason == .restart: .startedOver
        case .ended, .playing: .gotAway
        }
    }

    /// "Oct 12", in the phone's language.
    var dateText: String {
        (endedAt ?? createdAt).formatted(.dateTime.month(.abbreviated).day())
    }

    /// "4 rounds · Oct 12"
    var roundsAndDate: String {
        "\(String(localized: .mindMeldHistoryRowRounds(rounds.count))) · \(dateText)"
    }
}
