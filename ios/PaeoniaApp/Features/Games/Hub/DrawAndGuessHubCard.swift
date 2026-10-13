import SwiftUI

/// Draw & Guess on the hub: artwork, whose turn it is, who is here, and the score.
/// The Us tab shows the same card while the partner is in the game.
struct DrawAndGuessHubCard: View {
    let summary: DrawAndGuessHubSummary
    let partnerName: String
    let me: DrawAndGuessPlayer
    let partner: DrawAndGuessPlayer
    let open: () -> Void

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The art opens the game too. VoiceOver uses the button below instead.
            Button(action: open) {
                DrawAndGuessHubArtwork()
                    .overlay(alignment: .bottom) {
                        // Fades the art into the card below it.
                        LinearGradient(colors: [.clear, .paeoniaSurfacePrimary], startPoint: .top, endPoint: .bottom)
                            .frame(height: PaeoniaSpacing.space40)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .overlay(alignment: .top) { badges }

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(.gamesDrawAndGuessName)
                        .font(PaeoniaTypography.heroTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    statusLine
                }

                Button(action: open) {
                    Text(summary.status.actionTitle)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .accessibilityIdentifier("games.hub.drawAndGuess")
            }
            .padding([.horizontal, .bottom], PaeoniaSpacing.space20)
            .padding(.top, PaeoniaSpacing.space4)
        }
        .clipShape(shape)
        .background {
            shape
                .fill(.paeoniaSurfacePrimary)
                .shadow(color: .paeoniaAccentPrimary.opacity(summary.status.isYourTurn ? 0.25 : 0), radius: 24, y: 8)
        }
        .overlay {
            shape.strokeBorder(
                summary.status.isYourTurn ? Color.paeoniaAccentPrimary.opacity(0.6) : .paeoniaSurfacePressed,
                lineWidth: summary.status.isYourTurn ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
    }

    /// The partner chip on the left and the score on the right, over the art.
    private var badges: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            if summary.partnerIsHere {
                partnerHereChip
            }
            Spacer(minLength: 0)
            if let score = summary.score {
                DrawAndGuessScoreCapsule(score: score, me: me, partner: partner)
            }
        }
        .padding(PaeoniaSpacing.space12)
    }

    private var statusLine: some View {
        Text(summary.status.title(partnerName: partnerName))
            .font(summary.status.isYourTurn ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
            .foregroundStyle(summary.status.isYourTurn ? .paeoniaAccentPrimary : .paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Solid green so it stands out against both the plum card and the white art.
    private var partnerHereChip: some View {
        Label {
            Text(.gamesPartnerHereNow(partnerName))
                .font(PaeoniaTypography.caption.weight(.bold))
        } icon: {
            Circle()
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.paeoniaTextInverse)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaSuccess, in: Capsule())
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 6, y: 2)
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
