import SwiftUI

/// Opens the trail of one finished game. It looks the game up in the list the
/// history screen already loaded.
struct MindMeldHistoryDetailHost: View {
    let history: MindMeldHistoryViewModel
    let gameID: UUID

    var body: some View {
        if let game = history.games.first(where: { $0.id == gameID }) {
            MindMeldHistoryDetailScreen(game: game)
        } else {
            Color.paeoniaBackgroundSecondary
                .ignoresSafeArea()
                .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// A finished game: how it ended and when, then every round from the first pair
/// to the last, with the words coming closer.
struct MindMeldHistoryDetailScreen: View {
    let game: RemoteMindMeldHistoryGame

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space32) {
                Text(verbatim: headerLine)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mindMeld.history.detail.header")
                MindMeldTrailView(pairs: pairs, style: .detail)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space24)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("mindMeld.history.detail")
    }

    /// "Melded in 4 rounds · Oct 12", "Got away · Oct 12" or "Started over · Oct 12".
    private var headerLine: String {
        let outcome = switch game.ending {
        case .melded: String(localized: .mindMeldHistoryDetailMelded(game.rounds.count))
        case .gotAway: String(localized: .mindMeldHistoryRowGotAway)
        case .startedOver: String(localized: .mindMeldHistoryRowStartedOver)
        }
        return "\(outcome) · \(game.dateText)"
    }

    private var pairs: [MindMeldTrailView.Pair] {
        game.rounds.map { round in
            let isCounted = round.countedByUserID != nil
            return (
                mine: round.myWord,
                theirs: round.partnerWord,
                isMeld: round.outcome == .match || isCounted,
                isCounted: isCounted
            )
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        MindMeldHistoryDetailScreen(game: RemoteMindMeldHistoryGame(
            id: UUID(),
            gameNumber: 3,
            state: .melded,
            endReason: nil,
            endedByUserID: nil,
            createdAt: .now,
            endedAt: .now,
            meldNumber: 2,
            rounds: [
                RemoteMindMeldHistoryRound(
                    roundNumber: 1, myWord: "Ocean", partnerWord: "Sushi", outcome: .miss, countedByUserID: nil
                ),
                RemoteMindMeldHistoryRound(
                    roundNumber: 2, myWord: "Salt", partnerWord: "Fish", outcome: .miss, countedByUserID: nil
                ),
                RemoteMindMeldHistoryRound(
                    roundNumber: 3, myWord: "Fish", partnerWord: "Fish", outcome: .match, countedByUserID: nil
                ),
            ]
        ))
    }
    .preferredColorScheme(.dark)
}
#endif
