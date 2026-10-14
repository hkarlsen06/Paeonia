import SwiftUI

/// Exquisite corpse on the hub: artwork, whose turn it is, who is here, and how
/// many creatures the couple has made. The Home tab shows the same card while the
/// partner is in the game.
struct ExquisiteCorpseHubCard: View {
    let summary: ExquisiteCorpseHubSummary
    let context: GameHubCardContext
    let open: () -> Void
    /// Opens "Our creatures". Nil where the card has no room for the link.
    var openHistory: (() -> Void)?

    var body: some View {
        GameHubCardFrame(
            name: .exquisiteCorpseName,
            status: summary.status.title(partnerName: context.partnerName),
            actionTitle: summary.status.actionTitle,
            isYourTurn: summary.status.isYourTurn,
            context: context,
            actionIdentifier: "games.hub.exquisiteCorpse",
            open: open
        ) {
            ExquisiteCorpseHubPainting()
        } badge: {
            if summary.hasCreatures {
                ExquisiteCorpseCountCapsule(count: summary.figuresFinished)
            }
        } extras: {
            historyLink
        }
    }

    /// A quiet link to "Our creatures", once the couple has a finished creature.
    @ViewBuilder
    private var historyLink: some View {
        if summary.hasCreatures, let openHistory {
            Button(action: openHistory) {
                Label {
                    Text(.exquisiteCorpseHubHistory)
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("games.hub.exquisiteCorpse.history")
        }
    }
}

/// "12 creatures" over the artwork.
struct ExquisiteCorpseCountCapsule: View {
    let count: Int

    var body: some View {
        Text(.exquisiteCorpseHubCount(count))
            .font(PaeoniaTypography.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .gameCapsuleStyle()
            .accessibilityIdentifier("games.hub.exquisiteCorpse.count")
    }
}

extension ExquisiteCorpseHubSummary.Status {
    /// The game waits for this person, so the card stands out.
    var isYourTurn: Bool {
        switch self {
        case .yourTurn, .revealReady: true
        case .notStarted, .partnerDrawing, .partnerStarting: false
        }
    }

    func title(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .notStarted:
            .exquisiteCorpseHubStatusNotStarted
        case let .yourTurn(part):
            Self.yourTurnTitle(part)
        case let .partnerDrawing(part):
            Self.partnerDrawingTitle(part, partnerName: partnerName)
        case .revealReady:
            .exquisiteCorpseHubStatusRevealReady
        case .partnerStarting:
            .exquisiteCorpseWaitNewCreature(partnerName)
        }
    }

    private static func yourTurnTitle(_ part: ExquisiteCorpsePartKind) -> LocalizedStringResource {
        switch part {
        case .head: .exquisiteCorpseHubStatusYourTurnHead
        case .body: .exquisiteCorpseHubStatusYourTurnBody
        case .legs: .exquisiteCorpseHubStatusYourTurnLegs
        }
    }

    private static func partnerDrawingTitle(
        _ part: ExquisiteCorpsePartKind,
        partnerName: String
    ) -> LocalizedStringResource {
        switch part {
        case .head: .exquisiteCorpseHubStatusPartnerDrawingHead(partnerName)
        case .body: .exquisiteCorpseHubStatusPartnerDrawingBody(partnerName)
        case .legs: .exquisiteCorpseHubStatusPartnerDrawingLegs(partnerName)
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .notStarted: .exquisiteCorpseHubActionStart
        case .yourTurn: .exquisiteCorpseHubActionDraw
        case .revealReady: .exquisiteCorpseHubActionReveal
        case .partnerDrawing, .partnerStarting: .exquisiteCorpseHubActionOpen
        }
    }
}
