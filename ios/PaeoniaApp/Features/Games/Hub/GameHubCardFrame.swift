import SwiftUI

/// The card every game shows on the hub and, while the partner is in the game,
/// on the Us tab: the game's artwork with the partner chip and a trailing badge
/// over it, the name, a status line, the main button, and optional extras below.
/// The card glows while the game waits for this person.
struct GameHubCardFrame<Artwork: View, Badge: View, Extras: View>: View {
    let name: LocalizedStringResource
    let status: LocalizedStringResource
    let actionTitle: LocalizedStringResource
    let isYourTurn: Bool
    let context: GameHubCardContext
    /// The main button's identifier, such as `games.hub.drawAndGuess`.
    let actionIdentifier: String
    let open: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    /// Top trailing over the art, such as the score.
    @ViewBuilder let badge: () -> Badge
    /// Below the button, such as a quiet link to the game's history.
    @ViewBuilder let extras: () -> Extras

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The art opens the game too. VoiceOver uses the button below instead.
            Button(action: open) {
                artwork()
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
                    Text(name)
                        .font(PaeoniaTypography.heroTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    statusLine
                }

                Button(action: open) {
                    Text(actionTitle)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .accessibilityIdentifier(actionIdentifier)

                extras()
            }
            .padding([.horizontal, .bottom], PaeoniaSpacing.space20)
            .padding(.top, PaeoniaSpacing.space4)
        }
        .clipShape(shape)
        .background {
            shape
                .fill(.paeoniaSurfacePrimary)
                .shadow(color: .paeoniaAccentPrimary.opacity(isYourTurn ? 0.25 : 0), radius: 24, y: 8)
        }
        .overlay {
            shape.strokeBorder(
                isYourTurn ? Color.paeoniaAccentPrimary.opacity(0.6) : .paeoniaSurfacePressed,
                lineWidth: isYourTurn ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
    }

    /// The partner chip on the left and the badge on the right, over the art.
    private var badges: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            if context.partnerIsHere {
                partnerHereChip
            }
            Spacer(minLength: 0)
            badge()
        }
        .padding(PaeoniaSpacing.space12)
    }

    private var statusLine: some View {
        Text(status)
            .font(isYourTurn ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
            .foregroundStyle(isYourTurn ? .paeoniaAccentPrimary : .paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Solid green so it stands out against both the plum card and the white art.
    private var partnerHereChip: some View {
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
        .background(.paeoniaSuccess, in: Capsule())
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 6, y: 2)
    }
}

extension GameHubCardFrame where Badge == EmptyView, Extras == EmptyView {
    /// A card with no badge and no extras.
    init(
        name: LocalizedStringResource,
        status: LocalizedStringResource,
        actionTitle: LocalizedStringResource,
        isYourTurn: Bool,
        context: GameHubCardContext,
        actionIdentifier: String,
        open: @escaping () -> Void,
        @ViewBuilder artwork: @escaping () -> Artwork
    ) {
        self.init(
            name: name,
            status: status,
            actionTitle: actionTitle,
            isYourTurn: isYourTurn,
            context: context,
            actionIdentifier: actionIdentifier,
            open: open,
            artwork: artwork,
            badge: { EmptyView() },
            extras: { EmptyView() }
        )
    }
}
