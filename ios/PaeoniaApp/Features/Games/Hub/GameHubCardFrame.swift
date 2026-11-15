import SwiftUI

extension EnvironmentValues {
    @Entry var gameHubCardIsCompact = false
}

/// Adds the game's presence, score and "Not now" controls to the shared illustrated card.
struct GameHubCardFrame<Artwork: View, Badge: View, Extras: View>: View {
    let name: LocalizedStringResource
    let status: Text
    let actionTitle: LocalizedStringResource
    let isYourTurn: Bool
    let context: GameHubCardContext
    let actionIdentifier: String
    let open: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let extras: () -> Extras

    @Environment(\.gameHubCardIsCompact) private var isCompact

    var body: some View {
        PaeoniaIllustratedCard(
            title: name,
            status: status,
            actionTitle: actionTitle,
            needsAttention: isYourTurn,
            actionIdentifier: actionIdentifier,
            open: open,
            artwork: artwork,
            badge: { badge().environment(\.gameCapsuleIsOnArtwork, true) },
            header: { partnerHereChip },
            extras: extras,
            isCompact: isCompact,
            fillsHeight: context.isOnHub
        )
        .overlay(alignment: .topTrailing) {
            if let hide = context.hide, !isCompact {
                GameHubNotNowButton(action: hide)
                    .padding(PaeoniaSpacing.space4)
            }
        }
    }

    @ViewBuilder
    private var partnerHereChip: some View {
        if context.partnerIsHere {
            Label {
                Text(.gamesPartnerHereNow(context.partnerName))
                    .font(PaeoniaTypography.caption.weight(.bold))
            } icon: {
                Circle()
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.paeoniaTextInverse)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(.paeoniaPresence, in: Capsule())
            .padding(.bottom, PaeoniaSpacing.space4)
        }
    }
}

/// "Not now" on a card waiting for this person: a round button of the same tinted glass as
/// the score badge, so it reads on bright and dark paintings alike.
private struct GameHubNotNowButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            PaeoniaHaptics.selection()
            action()
        } label: {
            Image(systemName: "moon.zzz.fill")
                .font(.footnote.weight(.bold))
        }
        .buttonStyle(PaeoniaGlassCircleButtonStyle(
            face: 36,
            glass: .regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.75))
        ))
        .accessibilityLabel(Text(.gamesHubNotNow))
        .accessibilityHint(Text(.gamesHubNotNowHint))
        .accessibilityIdentifier("games.hub.notNow")
    }
}
