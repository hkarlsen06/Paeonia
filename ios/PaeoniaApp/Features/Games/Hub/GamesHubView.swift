import SwiftUI

/// The list of games. Draw & Guess is the only one so far.
struct GamesHubView: View {
    let viewModel: GamesViewModel
    @State private var isChangingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                if let summary = viewModel.hubSummary {
                    DrawAndGuessHubCard(
                        summary: summary,
                        partnerName: viewModel.partnerName,
                        me: viewModel.drawAndGuess.me,
                        partner: viewModel.drawAndGuess.partner
                    )
                }
                settingsRow
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth()
        }
        .refreshable { await viewModel.refresh() }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mainTabGames))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isChangingSettings) {
            GamesSettingsSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("games.hub")
    }

    /// How the couple plays and in which language, with a way to change both.
    private var settingsRow: some View {
        Button {
            isChangingSettings = true
        } label: {
            HStack(spacing: PaeoniaSpacing.space12) {
                Image(systemName: "slider.horizontal.3")
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .frame(width: PaeoniaSpacing.space24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(.gamesSettingsTitle)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    if let settings = viewModel.settings {
                        let playStyle = String(localized: settings.playStyle.title)
                        let language = String(localized: settings.language.title)
                        Text(verbatim: "\(playStyle) · \(language)")
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
            .padding(PaeoniaSpacing.cardContentPadding)
            .frame(minHeight: PaeoniaSpacing.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("games.hub.settings")
    }
}

/// Draw & Guess on the hub: whose turn it is, who is here, and the score.
struct DrawAndGuessHubCard: View {
    let summary: DrawAndGuessHubSummary
    let partnerName: String
    let me: DrawAndGuessPlayer
    let partner: DrawAndGuessPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            HStack(alignment: .center, spacing: PaeoniaSpacing.space12) {
                GamesBadge(systemImage: "pencil.and.scribble")
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(.gamesDrawAndGuessName)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    statusLine
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: PaeoniaSpacing.space8) {
                if let score = summary.score {
                    DrawAndGuessScoreCapsule(score: score, me: me, partner: partner)
                }
                if summary.partnerIsHere {
                    partnerHereChip
                }
            }

            NavigationLink(value: GamesDestination.drawAndGuess) {
                Text(summary.status.actionTitle)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier("games.hub.drawAndGuess")
        }
        .padding(PaeoniaSpacing.space20)
        .background(
            LinearGradient(
                colors: [.paeoniaSurfacePrimary, .paeoniaSurfaceSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
        }
    }

    private var statusLine: some View {
        Text(summary.status.title(partnerName: partnerName))
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var partnerHereChip: some View {
        Label {
            Text(.gamesPartnerHereNow(partnerName))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
        } icon: {
            Circle()
                .fill(.paeoniaSuccess)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaBackgroundSecondary.opacity(0.6), in: Capsule())
    }
}

extension DrawAndGuessHubSummary.Status {
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
