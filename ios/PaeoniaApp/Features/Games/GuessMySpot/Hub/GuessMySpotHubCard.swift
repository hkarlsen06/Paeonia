import SwiftUI

/// Guess my spot on the hub: artwork, whose turn it is, the couple's shared points,
/// and a quiet link to "Our guesses". The Home tab shows the same card while the
/// partner is in the game.
struct GuessMySpotHubCard: View {
    let summary: GuessMySpotHubSummary
    let context: GameHubCardContext
    let me: GamePlayer
    let partner: GamePlayer
    let open: () -> Void
    /// Opens "Our guesses". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    var body: some View {
        GameHubCardFrame(
            name: .guessMySpotTitle,
            status: Text(summary.status.title(partnerName: context.partnerName)),
            actionTitle: summary.status.actionTitle,
            isYourTurn: summary.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.guessMySpot",
            open: open,
            artwork: { GuessMySpotHubArtwork() },
            badge: { badge },
            extras: { historyLink }
        )
    }

    @ViewBuilder
    private var badge: some View {
        if !summary.score.isEmpty {
            GuessMySpotScoreCapsule(score: summary.score, me: me, partner: partner, onHub: true)
                .accessibilityIdentifier("guessMySpot.stats")
        }
    }

    @ViewBuilder
    private var historyLink: some View {
        if summary.hasHistory, let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.guessMySpotHistoryTitle)
                } icon: {
                    Image(systemName: "map")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.guessMySpot.history")
        }
    }
}

extension GuessMySpotHubSummary.Status {
    func title(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .new: .guessMySpotHubStatusNew(partnerName)
        case .send: .guessMySpotHubStatusSend
        case .guess: .guessMySpotHubStatusGuess(partnerName)
        case .waiting: .guessMySpotHubStatusWaiting(partnerName)
        case .choosing: .guessMySpotHubStatusChoosing(partnerName)
        case .reveal: .guessMySpotHubStatusReveal
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .new: .guessMySpotHubPlay
        case .send: .guessMySpotHubSend
        case .guess: .guessMySpotHubGuess
        case .waiting, .choosing: .guessMySpotHubOpen
        case .reveal: .guessMySpotHubSeeReveal
        }
    }
}
