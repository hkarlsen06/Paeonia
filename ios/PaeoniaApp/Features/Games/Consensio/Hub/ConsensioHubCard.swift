import SwiftUI

/// Consensio on the hub: artwork, whose turn it is, the couple's shared points,
/// and a quiet link to "What we know". The Home tab shows the same card while the
/// partner is in the game.
struct ConsensioHubCard: View {
    let summary: ConsensioHubSummary
    let context: GameHubCardContext
    let open: () -> Void
    /// Opens "What we know". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    var body: some View {
        GameHubCardFrame(
            name: .consensioTitle,
            status: Text(summary.status.title(partnerName: context.partnerName)),
            actionTitle: summary.status.actionTitle,
            isYourTurn: summary.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.consensio",
            open: open,
            artwork: { ConsensioHubArtwork() },
            badge: { badge },
            extras: { historyLink }
        )
    }

    @ViewBuilder
    private var badge: some View {
        if summary.sharedPoints > 0 {
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: "heart.fill")
                    .gameCapsuleIconStyle()
                    .accessibilityHidden(true)
                Text(.consensioStatsPoints(summary.sharedPoints))
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .gameCapsuleStyle()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.consensioPointsTogether(summary.sharedPoints)))
            .accessibilityIdentifier("consensio.stats")
        }
    }

    @ViewBuilder
    private var historyLink: some View {
        if summary.hasHistory, let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.consensioHistoryTitle)
                } icon: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.consensio.history")
        }
    }
}

extension ConsensioHubSummary.Status {
    func title(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .new: .consensioHubStatusNew(partnerName)
        case .place: .consensioHubStatusPlace
        case .guess: .consensioHubStatusGuess(partnerName)
        case .waiting: .consensioHubStatusWaiting(partnerName)
        case .choosing: .consensioHubStatusChoosing(partnerName)
        case .reveal: .consensioHubStatusReveal
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .new: .consensioHubPlay
        case .place: .consensioHubPick
        case .guess: .consensioHubGuess
        case .waiting, .choosing: .consensioHubOpen
        case .reveal: .consensioHubSeeReveal
        }
    }
}
