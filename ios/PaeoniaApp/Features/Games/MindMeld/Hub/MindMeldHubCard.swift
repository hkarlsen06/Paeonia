import SwiftUI

/// Mind Meld on the hub: artwork, whose turn it is, how many times the couple has
/// melded, and a quiet link to "Our melds". The Home tab shows the same card while
/// the partner is in the game.
struct MindMeldHubCard: View {
    let summary: MindMeldHubSummary
    let context: GameHubCardContext
    let open: () -> Void
    /// Opens "Our melds". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    var body: some View {
        GameHubCardFrame(
            name: .mindMeldTitle,
            status: Text(summary.status.title(partnerName: context.partnerName)),
            actionTitle: summary.status.actionTitle,
            isYourTurn: summary.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.mindMeld",
            open: open,
            artwork: { MindMeldHubArtwork() },
            badge: { badge },
            extras: { historyLink }
        )
    }

    @ViewBuilder
    private var badge: some View {
        if summary.melds > 0 {
            MindMeldStatsCapsule(melds: summary.melds)
        }
    }

    @ViewBuilder
    private var historyLink: some View {
        if summary.hasFinishedGames, let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.mindMeldHistoryTitle)
                } icon: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.mindMeld.history")
        }
    }
}

extension MindMeldHubSummary.Status {
    func title(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .new: .mindMeldHubStatusNew
        case let .open(round): .mindMeldHubStatusOpen(round)
        case .partnerLocked: .mindMeldHubStatusPartnerLocked(partnerName)
        case .waiting: .mindMeldHubStatusWaiting(partnerName)
        case .reveal: .mindMeldHubStatusReveal
        case let .melded(rounds): .mindMeldHubStatusMelded(rounds)
        case .gotAway: .mindMeldHubStatusGotAway
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .new, .open: .mindMeldHubPlay
        case .partnerLocked: .mindMeldHubPick
        case .waiting: .mindMeldHubOpen
        case .reveal: .mindMeldHubSeeWords
        case .melded, .gotAway: .mindMeldRevealPlayAgain
        }
    }
}
