import SwiftUI

/// The card every game shows on the hub and, while the partner is in the game,
/// on the Home tab. The game's picture runs behind the whole card. A badge such as the
/// score floats at the top center of its scene. Below, where the picture goes out of
/// focus, come the partner chip, the name, a status line, the main button, and optional
/// extras, centered. The card glows while the game waits for this person.
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
    /// At the top center, over the picture, such as the score.
    @ViewBuilder let badge: () -> Badge
    /// Below the button, such as a quiet link to the game's history.
    @ViewBuilder let extras: () -> Extras

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The scene part of the picture opens the game too. VoiceOver uses the button
            // below instead.
            Button(action: open) {
                Color.clear
                    .aspectRatio(1 / GameHubArtworkLayout.sceneShare, contentMode: .fit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            textBlock
        }
        // The picture runs behind the whole card, text included.
        .background(alignment: .top) { artwork() }
        .overlay(alignment: .top) {
            badge()
                .environment(\.gameCapsuleIsOnArtwork, true)
                .padding(.top, PaeoniaSpacing.space12)
                // The scene is only so tall, so the badge stops growing before it covers it.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .clipShape(shape)
        .background {
            shape
                .fill(.paeoniaBackgroundSecondary)
                .shadow(color: .paeoniaAccentPrimary.opacity(isYourTurn ? 0.25 : 0), radius: 24, y: 8)
        }
        .overlay {
            shape.strokeBorder(
                isYourTurn ? Color.paeoniaAccentPrimary.opacity(0.6) : .paeoniaSurfacePressed,
                lineWidth: isYourTurn ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
    }

    /// The partner chip, the name, the status, the button and the extras, centered under
    /// the picture's centered scene.
    private var textBlock: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            VStack(spacing: PaeoniaSpacing.space4) {
                if context.partnerIsHere {
                    partnerHereChip
                        .padding(.bottom, PaeoniaSpacing.space4)
                }
                Text(name)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                statusLine
            }
            .frame(maxWidth: .infinity)

            Button(action: open) {
                Text(actionTitle)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier(actionIdentifier)

            extras()
        }
        .padding([.horizontal, .bottom], PaeoniaSpacing.space20)
        .padding(.top, PaeoniaSpacing.space4)
        .background(alignment: .top) { textScrim }
    }

    /// A light shadow under the text, on top of the backdrop's Gaussian blur
    /// (`GameHubArtwork`). It fades in with the blur and deepens toward the bottom, where
    /// the button and links sit. `docs/games/hub-artwork.md` has the contrast this keeps.
    private var textScrim: some View {
        let shadow = Color.paeoniaBackgroundSecondary
        return LinearGradient(
            colors: [
                shadow.opacity(GameHubTextScrim.shadowAtName),
                shadow.opacity(GameHubTextScrim.shadowAtBottom),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: GameHubArtworkLayout.blurFadeIn)
                Color.black
            }
        }
        .padding(.top, -GameHubArtworkLayout.blurLead)
    }

    /// White and bold on your turn. Pink text can't keep 4.5:1 on a blurred pink backdrop,
    /// and the card's pink glow already says it is your turn.
    private var statusLine: some View {
        Text(status)
            .font(isYourTurn ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
            .foregroundStyle(isYourTurn ? .paeoniaTextPrimary : .paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Solid green, a live signal centered above the name.
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
    }
}

/// How dark the shadow under the card's text is, from the name to the bottom. Kept in step
/// with `art_asset.py text` in the paeonia-illustrations skill, which checks the contrast.
/// A generic view can't hold static stored values, so they live here.
private enum GameHubTextScrim {
    static let shadowAtName = 0.25
    static let shadowAtBottom = 0.5
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
