import SwiftUI

extension EnvironmentValues {
    /// True in the hub's grid, where a game's card is a small tile: the picture, the name
    /// and the status line, and the whole tile opens the game.
    @Entry var gameHubCardIsCompact = false
}

/// The card every game shows on the hub and, while the partner is in the game,
/// on the Home tab. The game's picture runs behind the whole card. A badge such as the
/// score floats at the top center of its scene. Below, where the picture goes out of
/// focus, come the partner chip, the name, a status line, the main button, and optional
/// extras, centered. The card glows while the game waits for this person. The daily
/// question card on the Home tab uses the frame too, with no partner chip.
///
/// In the hub's grid (`gameHubCardIsCompact`) the card is a small tile with the same
/// picture and beat, the name and the status line. It has no badge, partner chip, button
/// or extras, and a tap anywhere opens the game.
struct GameHubCardFrame<Artwork: View, Badge: View, Extras: View>: View {
    let name: LocalizedStringResource
    /// A `Text`, so a card can show a string that is not in the String Catalog, such as
    /// today's question.
    let status: Text
    let actionTitle: LocalizedStringResource
    let isYourTurn: Bool
    /// Nil on a card that is not a game, so it has no partner chip.
    let context: GameHubCardContext?
    /// The main button's identifier, such as `games.hub.drawAndGuess`.
    let actionIdentifier: String
    let open: () -> Void
    /// While set, the name and status show as placeholders, both buttons are off, and
    /// VoiceOver reads this instead of the name. The layout keeps its height.
    var loadingLabel: LocalizedStringResource?
    @ViewBuilder let artwork: () -> Artwork
    /// At the top center, over the picture, such as the score.
    @ViewBuilder let badge: () -> Badge
    /// Below the button, such as a quiet link to the game's history.
    @ViewBuilder let extras: () -> Extras

    private var isLoading: Bool { loadingLabel != nil }

    @Environment(\.gameHubCardIsCompact) private var isCompact

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isCompact ? PaeoniaRadius.radius20 : PaeoniaRadius.radius28,
            style: .continuous
        )
    }

    var body: some View {
        if isCompact {
            tile
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The scene part of the picture opens the game too. VoiceOver uses the button
            // below instead.
            Button(action: open) {
                Color.clear
                    .aspectRatio(1 / GameHubArtworkLayout.sceneShare, contentMode: .fit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityHidden(true)

            textBlock
        }
        // On the hub, two cards side by side on iPad match the taller one, so their names
        // and buttons line up. The space goes at the bottom.
        .frame(maxHeight: context?.isOnHub == true ? .infinity : nil, alignment: .top)
        .overlay(alignment: .top) {
            badge()
                .environment(\.gameCapsuleIsOnArtwork, true)
                .padding(.top, PaeoniaSpacing.space12)
                // The scene is only so tall, so the badge stops growing before it covers it.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .modifier(framing)
    }

    /// The grid's small card: the scene, then the name on one line and room for three
    /// lines of status, so every tile has the same height.
    private var tile: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                Color.clear
                    .aspectRatio(1 / GameHubArtworkLayout.sceneShare, contentMode: .fit)
                VStack(spacing: PaeoniaSpacing.space4) {
                    Text(name)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                    status
                        .font(isYourTurn ? PaeoniaTypography.caption.weight(.semibold) : PaeoniaTypography.caption)
                        .foregroundStyle(isYourTurn ? .paeoniaTextPrimary : .paeoniaTextSecondary)
                        .lineLimit(3, reservesSpace: true)
                        .contentTransition(.opacity)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .redacted(reason: isLoading ? .placeholder : [])
                .padding([.horizontal, .bottom], PaeoniaSpacing.space12)
                .padding(.top, PaeoniaSpacing.space4)
                .background(alignment: .top) { textScrim }
            }
            .modifier(framing)
            .contentShape(shape)
        }
        .buttonStyle(.paeoniaPressableCard)
        .disabled(isLoading)
        .accessibilityLabel(loadingLabel.map { Text($0) } ?? Text(name))
        .accessibilityValue(isLoading ? Text(verbatim: "") : status)
        .accessibilityIdentifier(actionIdentifier)
    }

    /// The picture behind the whole card, text included, the rounded shape, and the glow
    /// while the game waits for this person.
    private var framing: GameHubCardFraming<Artwork> {
        GameHubCardFraming(shape: shape, isYourTurn: isYourTurn, artwork: artwork)
    }

    /// The partner chip, the name, the status, the button and the extras, centered under
    /// the picture's centered scene.
    private var textBlock: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            VStack(spacing: PaeoniaSpacing.space4) {
                if let context, context.partnerIsHere {
                    partnerHereChip(context)
                        .padding(.bottom, PaeoniaSpacing.space4)
                }
                Text(name)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .accessibilityLabel(loadingLabel.map { Text($0) } ?? Text(name))
                    .accessibilityAddTraits(.isHeader)
                statusLine
                    .accessibilityHidden(isLoading)
            }
            .frame(maxWidth: .infinity)
            .redacted(reason: isLoading ? .placeholder : [])

            Button {
                PaeoniaHaptics.gameContinued()
                open()
            } label: {
                Text(actionTitle)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(isLoading)
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
        status
            .font(isYourTurn ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
            .foregroundStyle(isYourTurn ? .paeoniaTextPrimary : .paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .contentTransition(.opacity)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Solid green, a live signal centered above the name.
    private func partnerHereChip(_ context: GameHubCardContext) -> some View {
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

/// What the full card and the tile share around their content.
private struct GameHubCardFraming<Artwork: View>: ViewModifier {
    let shape: RoundedRectangle
    let isYourTurn: Bool
    let artwork: () -> Artwork

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) { artwork() }
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
        status: Text,
        actionTitle: LocalizedStringResource,
        isYourTurn: Bool,
        context: GameHubCardContext?,
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
