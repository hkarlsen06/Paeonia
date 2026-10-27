import SwiftUI

nonisolated enum GameConversationLoadState: Hashable {
    case loading, failed, offline, removed
}

/// The complete result is the first chat row and scrolls away with the messages.
struct GameConversationHeader: View {
    let source: GameConversationSource
    let result: GameConversationResult?
    let participants: DailyChallengeParticipants
    var loadState = GameConversationLoadState.loading
    var onRetry: () -> Void = {}

    private var people: GameConversationPeople { GameConversationPeople(participants: participants) }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space20) {
            VStack(spacing: PaeoniaSpacing.space4) {
                Text(source.kind.name)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let result {
                    Text(result.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            if let result {
                content(result)
            } else if loadState == .removed {
                Text(.gamesConversationUnavailable)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            } else if loadState == .loading {
                ProgressView().tint(.paeoniaAccentPrimary)
            } else {
                PaeoniaLoadFailureView(
                    failure: loadState == .offline ? .offline : .other,
                    offlineTitle: .gamesConversationOfflineTitle,
                    offlineMessage: .gamesConversationOfflineMessage,
                    failedMessage: .gamesConversationFailedMessage
                ) {
                    Button(action: onRetry) { Text(.commonTryAgain) }
                        .buttonStyle(PaeoniaSecondaryButtonStyle())
                }
            }
        }
        .padding(PaeoniaSpacing.space16)
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .background(.paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20))
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("game.conversation.result")
    }

    @ViewBuilder
    private func content(_ result: GameConversationResult) -> some View {
        switch result {
        case .mindMeld(let game):
            mindMeld(game)
        case .drawAndGuess(let round, let guesses):
            GameConversationDrawing(assetID: round.drawingMediaAssetID)
            Text(verbatim: round.word).font(PaeoniaTypography.sectionTitle)
            Text(.gamesConversationGuesses(people.name(for: round.guesserUserID)))
                .font(PaeoniaTypography.caption)
            ForEach(Array(guesses.enumerated()), id: \.offset) { _, guess in
                Text(verbatim: guess).font(PaeoniaTypography.body)
            }
        case .consensio(let round):
            consensio(round)
        case .guessMySpot(let round):
            GameConversationSpot(round: round, people: people)
        case .storyChain(let story):
            storyChain(story)
        case .exquisiteCorpse(let figure):
            creature(figure)
        case .board(let kind, let game):
            GameConversationBoard(kind: kind, game: game, people: people)
        }
    }

    private func creature(_ figure: RemoteExquisiteCorpseFigure) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            VStack(spacing: 0) {
                ForEach(figure.parts.sorted { $0.partIndex < $1.partIndex }) { part in
                    if let assetID = part.drawingMediaAssetID {
                        GameConversationDrawing(assetID: assetID)
                    }
                }
            }
            ExquisiteCorpseRevealCredits(
                parts: figure.parts.compactMap { part in
                    guard let kind = part.kind else { return nil }
                    return ExquisiteCorpseRevealContent.Part(
                        kind: kind, drawing: nil, drawerIsMe: part.drawerUserID == participants.currentUserID,
                        drawer: GamePlayer(name: people.name(for: part.drawerUserID)), idea: part.idea?.text
                    )
                })
        }
    }

    private func mindMeld(_ game: RemoteMindMeldHistoryGame) -> some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            HStack {
                Text(.dailyChallengeChoiceYou).foregroundStyle(.paeoniaPartnerOne)
                Spacer()
                Text(verbatim: participants.partnerName).foregroundStyle(.paeoniaPartnerTwo)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            MindMeldTrailView(
                pairs: game.rounds.map {
                    (
                        mine: $0.myWord, theirs: $0.partnerWord,
                        isMeld: $0.outcome == .match || $0.countedByUserID != nil, isCounted: $0.countedByUserID != nil
                    )
                }, style: .detail)
            Text(.mindMeldHistoryRowRounds(game.rounds.count))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    @ViewBuilder
    private func consensio(_ round: RemoteConsensioRound) -> some View {
        Text(verbatim: round.subject).font(PaeoniaTypography.sectionTitle)
        if let spot = round.spot, let guess = round.guess {
            ConsensioScale(
                subject: round.subject, leftEnd: round.leftEnd, rightEnd: round.rightEnd,
                pins: [
                    .init(id: "spot", position: spot, style: people.style(for: round.placerUserID)),
                    .init(id: "guess", position: guess, style: people.style(for: round.guesserUserID)),
                ],
                thread: .init(from: guess, to: spot, progress: 1)
            )
            Text(
                .gamesConversationSpot(
                    people.name(for: round.placerUserID), ConsensioScaleValue.string(spot, in: round)))
            Text(
                .gamesConversationGuess(
                    people.name(for: round.guesserUserID), ConsensioScaleValue.string(guess, in: round)))
        }
    }

    private func storyChain(_ story: RemoteStoryChainStory) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if let title = story.title {
                Text(verbatim: title).font(PaeoniaTypography.sectionTitle)
            }
            if let opening = story.openingText {
                Text(verbatim: opening).foregroundStyle(.paeoniaTextSecondary)
            }
            ForEach(story.lines) { line in
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(verbatim: people.name(for: line.authorUserID))
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(
                            line.authorUserID == participants.currentUserID ? .paeoniaPartnerOne : .paeoniaPartnerTwo)
                    Text(verbatim: line.text).font(PaeoniaTypography.body)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GameConversationPeople {
    let participants: DailyChallengeParticipants

    func name(for userID: UUID) -> String {
        userID == participants.currentUserID ? String(localized: .consensioRevealYou) : participants.partnerName
    }

    func style(for userID: UUID) -> BoardPieceStyle {
        let mine = userID == participants.currentUserID
        return BoardPieceStyle(
            color: mine ? .boardGameMine : .boardGamePartner,
            mark: nil,
            initial: BoardPieceStyle.initial(
                of: mine ? participants.currentDisplayName ?? name(for: userID) : participants.partnerName)
        )
    }
}
