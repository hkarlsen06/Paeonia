import SwiftUI

/// Story Chain on the hub: artwork, whose turn it is, who is here, and how many
/// stories the two of them have finished. The Home tab shows the same card while
/// the partner is in the game.
struct StoryChainHubCard: View {
    let summary: StoryChainHubSummary
    let context: GameHubCardContext
    let partnerName: String
    let open: () -> Void
    /// Opens "Our stories". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    var body: some View {
        GameHubCardFrame(
            name: .storyChainName,
            status: Text(summary.status.title(partnerName: partnerName)),
            actionTitle: summary.status.actionTitle,
            isYourTurn: summary.status.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.storyChain",
            open: open
        ) {
            StoryChainHubArtwork()
        } badge: {
            finishedBadge
        } extras: {
            historyLink
        }
    }

    // MARK: Finished stories

    /// A capsule beside the name with how many stories the couple has finished.
    @ViewBuilder
    private var finishedBadge: some View {
        if summary.finishedCount > 0 {
            Label {
                Text(.storyChainHubFinishedCount(summary.finishedCount))
            } icon: {
                Image(systemName: "books.vertical")
                    .gameCapsuleIconStyle()
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .gameCapsuleStyle()
            .accessibilityIdentifier("games.hub.storyChain.finished")
        }
    }

    /// A quiet link to "Our stories", once the couple has a finished story.
    @ViewBuilder
    private var historyLink: some View {
        if summary.hasHistory, let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.storyChainHistoryTitle)
                } icon: {
                    Image(systemName: "books.vertical")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.storyChain.history")
        }
    }
}

extension StoryChainHubSummary.Status {
    func title(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .notStarted: .storyChainHubSubtitle
        case .yourTurnToStart: .storyChainHubStatusStart
        case .yourTurnToWrite: .storyChainHubStatusWrite
        case .yourTurnToName: .storyChainHubStatusName
        case .readEnding: .storyChainHubStatusRead
        case .partnerTurn: .storyChainHubStatusPartnerTurn(partnerName)
        case .waitingForPartner: .gamesHubStatusWaiting(partnerName)
        }
    }

    /// "Write" where the turn involves writing, "Open" where it is reading or waiting.
    var actionTitle: LocalizedStringResource {
        switch self {
        case .yourTurnToStart, .yourTurnToWrite, .yourTurnToName: .storyChainHubActionWrite
        case .notStarted, .readEnding, .partnerTurn, .waitingForPartner: .storyChainHubActionOpen
        }
    }
}
