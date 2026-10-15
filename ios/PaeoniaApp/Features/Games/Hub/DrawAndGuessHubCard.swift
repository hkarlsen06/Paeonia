import SwiftUI

/// Draw & Guess on the hub: artwork, whose turn it is, who is here, and the score.
/// The Home tab shows the same card while the partner is in the game.
struct DrawAndGuessHubCard: View {
    let summary: DrawAndGuessHubSummary
    let context: GameHubCardContext
    let me: GamePlayer
    let partner: GamePlayer
    let open: () -> Void
    /// Opens "Our drawings". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    var body: some View {
        GameHubCardFrame(
            name: .gamesDrawAndGuessName,
            status: Text(summary.status.title(partnerName: context.partnerName)),
            actionTitle: summary.status.actionTitle,
            isYourTurn: summary.status.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.drawAndGuess",
            open: open
        ) {
            DrawAndGuessHubArtwork()
        } badge: {
            if let score = summary.score {
                DrawAndGuessScoreCapsule(score: score, me: me, partner: partner)
            }
        } extras: {
            historyLink
        }
    }

    /// A quiet link to "Our drawings", once the couple has a finished drawing.
    @ViewBuilder
    private var historyLink: some View {
        if summary.hasDrawings, let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.gamesDrawAndGuessHistoryTitle)
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.history")
        }
    }
}

extension DrawAndGuessHubSummary.Status {
    /// The game waits for this person, so the card stands out.
    var isYourTurn: Bool {
        self == .yourTurnToDraw || self == .yourTurnToGuess
    }

    func title(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .notStarted: .gamesHubStatusNotStarted
        case .yourTurnToDraw: .gamesHubStatusYourTurnToDraw
        case .yourTurnToGuess: .gamesHubStatusYourTurnToGuess
        case .partnerIsDrawing: .gamesHubStatusPartnerDrawing(partnerName)
        case .waitingForPartner: .gamesHubStatusWaiting(partnerName)
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .notStarted: .gamesHubActionStart
        case .yourTurnToDraw: .gamesHubActionDraw
        case .yourTurnToGuess: .gamesHubActionGuess
        case .partnerIsDrawing: .gamesHubActionWatch
        case .waitingForPartner: .gamesHubActionOpen
        }
    }
}
