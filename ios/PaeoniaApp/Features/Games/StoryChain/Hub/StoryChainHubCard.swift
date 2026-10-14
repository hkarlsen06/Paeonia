import SwiftUI

/// Story Chain on the hub: artwork, whose turn it is, who is here, and how many
/// stories the two of them have finished. The Us tab shows the same card while
/// the partner is in the game.
struct StoryChainHubCard: View {
    let summary: StoryChainHubSummary
    let context: GameHubCardContext
    let partnerName: String
    let open: () -> Void
    /// Opens "Our stories". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GameHubCardFrame(
            name: .storyChainName,
            status: summary.status.title(partnerName: partnerName),
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
            extras
        }
    }

    // MARK: Finished stories

    /// A capsule over the art. At accessibility text sizes it would crowd the
    /// partner chip, so the count moves under the button as a caption.
    @ViewBuilder
    private var finishedBadge: some View {
        if summary.finishedCount > 0, !dynamicTypeSize.isAccessibilitySize {
            Label {
                Text(.storyChainHubFinishedCount(summary.finishedCount))
            } icon: {
                Image(systemName: "books.vertical")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
            .accessibilityIdentifier("games.hub.storyChain.finished")
        }
    }

    @ViewBuilder
    private var extras: some View {
        if summary.finishedCount > 0, dynamicTypeSize.isAccessibilitySize {
            Text(.storyChainHubFinishedCount(summary.finishedCount))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(maxWidth: .infinity)
        }
        historyLink
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
        case .partnerWriting: .storyChainHubStatusPartnerWriting(partnerName)
        case .waitingForPartner: .gamesHubStatusWaiting(partnerName)
        }
    }

    /// "Write" where the turn involves writing, "Open" where it is reading or waiting.
    var actionTitle: LocalizedStringResource {
        switch self {
        case .yourTurnToStart, .yourTurnToWrite, .yourTurnToName: .storyChainHubActionWrite
        case .notStarted, .readEnding, .partnerWriting, .waitingForPartner: .storyChainHubActionOpen
        }
    }
}
