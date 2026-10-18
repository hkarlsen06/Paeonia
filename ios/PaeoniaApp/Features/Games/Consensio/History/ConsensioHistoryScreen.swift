import SwiftUI

/// "What we know": each partner's record as a guesser and the shared total, above
/// every guessed round, newest first. A row opens the round on its line.
struct ConsensioHistoryScreen: View {
    let viewModel: ConsensioHistoryViewModel

    static let cardShape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

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
        .navigationTitle(Text(.consensioHistoryTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
        .accessibilityIdentifier("consensio.history")
    }

    // MARK: Records

    @ViewBuilder
    private var records: some View {
        if let records = viewModel.records, records.mine.guesses + records.partner.guesses > 0 {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space16))
                layout {
                    column(viewModel.me, isMe: true, record: records.mine)
                    column(viewModel.partner, isMe: false, record: records.partner)
                }
                Label {
                    Text(.consensioPointsTogether(records.sharedPoints))
                } icon: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)
                }
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            }
            .accessibilityIdentifier("consensio.history.records")
        }
    }

    private func column(_ player: GamePlayer, isMe: Bool, record: RemoteConsensioGuesserRecord) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space8) {
                GameAvatar(player: player, isMe: isMe, size: 28)
                (isMe ? Text(.consensioRevealYou) : Text(verbatim: player.name))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            value(.consensioHistoryRecordsSpotOn, text: record.guesses > 0 ? record.spotOns.formatted() : nil)
            value(
                .consensioHistoryRecordsAverage,
                text: record.averageDistance.map { String(localized: .consensioHistoryRecordsAverageValue($0)) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PaeoniaSpacing.space16)
        .background(.paeoniaSurfaceSecondary, in: Self.cardShape)
        .accessibilityElement(children: .combine)
    }

    private func value(_ label: LocalizedStringResource, text: String?) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(label)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            if let text {
                Text(verbatim: text)
                    .font(PaeoniaTypography.title)
                    .monospacedDigit()
                    .foregroundStyle(.paeoniaTextPrimary)
            } else {
                Text(.consensioHistoryRecordsNone)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.rounds.isEmpty {
            list
        } else if viewModel.isLoading {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if let failure = viewModel.loadFailure {
            PaeoniaLoadFailureView(
                failure: failure,
                offlineTitle: .consensioOfflineTitle,
                offlineMessage: .consensioHistoryOfflineMessage,
                failedMessage: .consensioHistoryFailedMessage
            ) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
                .accessibilityIdentifier("consensio.history.retry")
            }
        } else {
            PaeoniaEmptyStateView(
                title: .consensioHistoryEmptyTitle,
                message: .consensioHistoryEmptyMessage,
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
        }
    }

    private var list: some View {
        LazyVStack(spacing: PaeoniaSpacing.space12) {
            ForEach(viewModel.rounds) { round in
                NavigationLink(value: GamesDestination.consensioHistoryDetail(round.id)) {
                    ConsensioHistoryRow(round: round, viewModel: viewModel)
                }
                .buttonStyle(.plain)
                .task { await viewModel.loadMoreIfNeeded(after: round) }
            }
            if viewModel.loadMoreFailed {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(.consensioHistoryLoadMoreFailed)
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
                    .accessibilityIdentifier("consensio.history.retryMore")
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.hasMore {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Row

/// One round: the subject, a small line with both pins in their places, and who
/// guessed, the points and the date.
private struct ConsensioHistoryRow: View {
    let round: RemoteConsensioRound
    let viewModel: ConsensioHistoryViewModel

    private var guesserName: String {
        round.guesserUserID == viewModel.currentUserID ? String(localized: .consensioRevealYou) : viewModel.partnerName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            HStack {
                Text(verbatim: round.subject)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Spacer(minLength: PaeoniaSpacing.space8)
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.bold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
            ConsensioMiniLine(
                spot: round.spot,
                guess: round.guess,
                spotColor: color(of: round.placerUserID),
                guessColor: color(of: round.guesserUserID)
            )
            Text(.consensioHistoryRowCaption(
                guesserName,
                String(localized: .consensioStatsPoints(round.knownPoints ?? 0)),
                (round.guessedAt ?? round.placedAt).formatted(.dateTime.month(.abbreviated).day())
            ))
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: ConsensioHistoryScreen.cardShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.consensioHistoryRowA11Y(
            round.subject,
            ConsensioScaleValue.string(round.spot, in: round),
            ConsensioScaleValue.string(round.guess, in: round),
            round.knownPoints ?? 0
        )))
        .accessibilityAddTraits(.isButton)
    }

    private func color(of userID: UUID) -> Color {
        userID == viewModel.currentUserID ? .boardGameMine : .boardGamePartner
    }
}

/// A thin track with two dots: the real spot and the guess.
struct ConsensioMiniLine: View {
    let spot: Int?
    let guess: Int?
    let spotColor: Color
    let guessColor: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (value: Int) in 5 + (width - 10) * CGFloat(value) / 100 }
            ZStack(alignment: .leading) {
                Capsule().fill(.paeoniaSurfacePrimary).frame(height: 3)
                if let spot, let guess {
                    Capsule()
                        .fill(Color.paeoniaInkGold.opacity(0.6))
                        .frame(width: abs(x(spot) - x(guess)), height: 3)
                        .offset(x: min(x(spot), x(guess)))
                }
                if let guess {
                    Circle().fill(guessColor).frame(width: 10, height: 10).offset(x: x(guess) - 5)
                }
                if let spot {
                    Circle().fill(spotColor).frame(width: 10, height: 10).offset(x: x(spot) - 5)
                }
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Detail

/// Opens one round. It looks it up in the list the history screen already loaded.
struct ConsensioHistoryDetailHost: View {
    let history: ConsensioHistoryViewModel
    let roundID: UUID

    var body: some View {
        if let round = history.round(roundID) {
            ConsensioHistoryDetailScreen(round: round, history: history)
        } else {
            Color.paeoniaBackgroundSecondary
                .ignoresSafeArea()
                .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// One round at full size: the topic, both pins on the line with the thread
/// between them, how close the guess came, and whose spot it was.
struct ConsensioHistoryDetailScreen: View {
    let round: RemoteConsensioRound
    let history: ConsensioHistoryViewModel

    private var placedByMe: Bool {
        round.placerUserID == history.currentUserID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                Text(verbatim: round.subject)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                ConsensioScale(
                    subject: round.subject,
                    leftEnd: round.leftEnd,
                    rightEnd: round.rightEnd,
                    pins: pins,
                    thread: thread
                )
                .accessibilityValue(Text(.consensioRevealStageA11Y(
                    ConsensioScaleValue.string(round.spot, in: round),
                    ConsensioScaleValue.string(round.guess, in: round)
                )))
                verdict
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space32)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("consensio.history.detail")
    }

    @ViewBuilder
    private var verdict: some View {
        if let distance = round.knownDistance {
            VStack(spacing: PaeoniaSpacing.space4) {
                Text(ConsensioRevealView.title(for: ConsensioRules.verdict(distance: distance)))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(placedByMe
                    ? .consensioHistoryDetailPlacedByYou
                    : .consensioHistoryDetailPlaced(history.partnerName))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    private func style(of userID: UUID, name: String) -> BoardPieceStyle {
        BoardPieceStyle(
            color: userID == history.currentUserID ? .boardGameMine : .boardGamePartner,
            mark: nil,
            initial: BoardPieceStyle.initial(of: name)
        )
    }

    private var pins: [ConsensioScale.Pin] {
        let placerName = placedByMe ? history.me.name : history.partnerName
        let guesserName = placedByMe ? history.partnerName : history.me.name
        var pins: [ConsensioScale.Pin] = []
        if let guess = round.guess {
            let guesser = style(of: round.guesserUserID, name: guesserName)
            pins.append(ConsensioScale.Pin(id: "guess", position: guess, style: guesser))
        }
        if let spot = round.spot {
            let placer = style(of: round.placerUserID, name: placerName)
            pins.append(ConsensioScale.Pin(id: "spot", position: spot, style: placer))
        }
        return pins
    }

    private var thread: ConsensioScale.Thread? {
        guard let spot = round.spot, let guess = round.guess, abs(spot - guess) >= 4 else { return nil }
        return ConsensioScale.Thread(from: guess, to: spot, progress: 1)
    }
}
