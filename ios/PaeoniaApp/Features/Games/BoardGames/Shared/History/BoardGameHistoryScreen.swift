import SwiftUI

/// "Past games": every finished game of one board game, newest first. A row
/// plays that game again.
struct BoardGameHistoryScreen<Board: BoardGameRules>: View {
    let viewModel: BoardGameHistoryViewModel
    /// The live game, for the players' names, photos and pieces.
    let players: BoardGameViewModel<Board>

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space32)
                .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await viewModel.load() }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.boardGamesHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Runs again when the screen comes back from a replay.
        .task { await viewModel.load() }
        .accessibilityIdentifier("boardGames.history")
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.games.isEmpty {
            list
        } else if viewModel.isLoading {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if let failure = viewModel.loadFailure {
            failureState(failure)
        } else {
            PaeoniaEmptyStateView(
                title: .boardGamesHistoryEmptyTitle,
                message: .boardGamesHistoryEmptyMessage,
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    private var list: some View {
        LazyVStack(spacing: PaeoniaSpacing.space12) {
            ForEach(viewModel.games) { game in
                NavigationLink(value: GamesDestination.boardGameReplay(viewModel.kind, gameNumber: game.gameNumber)) {
                    BoardGameHistoryRow(
                        game: game,
                        winner: winner(of: game),
                        me: players.meInfo,
                        partner: players.partnerInfo
                    )
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

    private func winner(of game: RemoteBoardGameHistoryGame) -> BoardGameWinner {
        switch game.winnerUserID {
        case nil: .draw
        case players.currentUserID: .me
        default: .partner
        }
    }

    /// The last row's own load runs once, so this button is the way to try again.
    private var loadMoreFailedRow: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.boardGamesHistoryLoadMoreFailed)
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
            .accessibilityIdentifier("boardGames.history.retryMore")
        }
        .frame(maxWidth: .infinity)
    }

    private func failureState(_ failure: PaeoniaFailure) -> some View {
        PaeoniaLoadFailureView(
            failure: failure,
            offlineMessage: .boardGamesHistoryOfflineMessage,
            failedMessage: .boardGamesHistoryFailedMessage
        ) {
            Button {
                Task { await viewModel.load() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
            .accessibilityIdentifier("boardGames.history.retry")
        }
    }
}

// MARK: - Row

/// One finished game: the winner's photo, who won, the number of moves and the
/// date, and the bet when there was one.
private struct BoardGameHistoryRow: View {
    let game: RemoteBoardGameHistoryGame
    let winner: BoardGameWinner
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            badge
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(title)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(verbatim: details)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                if let stake = game.stake {
                    Text(.boardGamesStakePlayingFor(stake))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: PaeoniaSpacing.space8)
            Image(systemName: "play.fill")
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("boardGames.history.row")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
    }

    @ViewBuilder
    private var badge: some View {
        switch winner {
        case .me:
            BoardGameAvatar(player: me, size: 36)
        case .partner:
            BoardGameAvatar(player: partner, size: 36)
        case .draw:
            Image(systemName: "equal")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: 36, height: 36)
                .background(.paeoniaBackgroundSecondary, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var title: LocalizedStringResource {
        switch winner {
        case .me: .boardGamesResultTitleYouWon
        case .partner: .boardGamesResultTitlePartnerWon(partner.name)
        case .draw: .boardGamesResultTitleDraw
        }
    }

    /// "39 moves · Oct 12, 2026", in the phone's language.
    private var details: String {
        let moves = String(localized: .boardGamesHistoryRowMoves(game.moves.count))
        return "\(moves) · \(game.finishedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}
