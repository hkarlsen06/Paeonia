import SwiftUI

nonisolated enum PaeoniaIllustratedCardLayout {
    static let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)

    /// The canvas the picture is laid out on, in pixels. It is as wide as the card and
    /// anchored at the top, so one pixel is `cardWidth / 1024` points.
    static let canvasSize = CGSize(width: 1_024, height: 1_536)
    /// How far down the scene reaches, as a share of the card's width. The card's text
    /// starts below it, so the scene keeps its shape at every card width.
    static let sceneShare = Scene.full.share
    /// The backdrop goes out of focus under the text: a Gaussian blur that fades in over
    /// `blurFadeIn` points, starting `blurLead` points above where the text starts.
    static let blurRadius: CGFloat = 20
    static let blurLead: CGFloat = 24
    static let blurFadeIn: CGFloat = 40
    static let shadowAtTitle = 0.25
    static let shadowAtBottom = 0.5

    /// The rows of the canvas a full card's picture shows above its text, and how large
    /// the scene's objects stand in them.
    struct Scene: Sendable {
        /// The canvas row at the top of the picture.
        let top: CGFloat
        /// The canvas row where the text starts. `art_asset.py text` checks the backdrop from here down.
        let textTop: CGFloat
        /// The objects' size against the backdrop. The scene shrinks toward the middle of
        /// the main object's lower edge, which keeps the gap above the text in proportion.
        let objectScale: CGFloat
        /// Where the badge floats. Beside the objects when the picture is too short to hold
        /// it above them.
        let badgeAlignment: Alignment

        /// The picture's height as a share of the card's width.
        var share: CGFloat { (textTop - top) / canvasSize.width }

        /// Where the main object's lower edge lands, in canvas rows.
        var objectBase: CGFloat { textTop - (Self.full.textTop - Self.fullObjectBase) * objectScale }

        static let fullObjectBase: CGFloat = 640
        /// The whole scene, as on the Us tab, the daily question card and the hub's tiles.
        static let full = Scene(top: 0, textTop: 720, objectScale: 1, badgeAlignment: .top)
        /// The Games hub's full cards: the bare wall of the badge zone is cut away, the
        /// objects shrink to 70 percent, and the badge moves to the top left corner, so the
        /// next card's name shows on the same screen.
        static let hubBanner = Scene(top: 110, textTop: 520, objectScale: 0.7, badgeAlignment: .topLeading)
    }
}

extension EnvironmentValues {
    /// The scene a full illustrated card shows. Tiles always show the whole scene.
    @Entry var paeoniaIllustratedScene = PaeoniaIllustratedCardLayout.Scene.full
}

/// An illustrated card with a title, status, primary action and optional content.
struct PaeoniaIllustratedCard<Artwork: View, Badge: View, Header: View, Extras: View>: View {
    let title: LocalizedStringResource
    /// A `Text`, so a card can show a string that is not in the String Catalog, such as
    /// today's question.
    let status: Text
    let actionTitle: LocalizedStringResource
    let needsAttention: Bool
    let actionIdentifier: String
    let open: () -> Void
    /// While set, the title and status hide, actions are off, and VoiceOver reads this label.
    var loadingLabel: LocalizedStringResource?
    @ViewBuilder let artwork: () -> Artwork
    /// At the top center, over the picture, such as the score.
    @ViewBuilder let badge: () -> Badge
    /// Optional content above the title, such as partner presence.
    @ViewBuilder let header: () -> Header
    /// Optional content below the primary action.
    @ViewBuilder let extras: () -> Extras

    private var isLoading: Bool { loadingLabel != nil }

    var isCompact = false
    var fillsHeight = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.paeoniaIllustratedScene) private var scene

    private var shape: RoundedRectangle { PaeoniaIllustratedCardLayout.shape }

    var body: some View {
        if isCompact {
            tile
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The picture opens the destination too. VoiceOver uses the primary button.
            Button(action: open) {
                Color.clear
                    .aspectRatio(1 / scene.share, contentMode: .fit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityHidden(true)

            textBlock
        }
        // Grid cards can fill their row's height, with extra room at the bottom.
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .overlay(alignment: scene.badgeAlignment) {
            if !dynamicTypeSize.isAccessibilitySize {
                badge()
                    .padding(.top, PaeoniaSpacing.space12)
                    .padding(.leading, scene.badgeAlignment == .topLeading ? PaeoniaSpacing.space12 : 0)
            }
        }
        .modifier(framing)
    }

    /// The grid's small card keeps a consistent height unless accessibility text needs more room.
    private var tile: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                Color.clear
                    .aspectRatio(1 / PaeoniaIllustratedCardLayout.sceneShare, contentMode: .fit)
                VStack(spacing: PaeoniaSpacing.space4) {
                    Text(title)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                    tileStatus
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .paeoniaLoadingReveal(isLoading)
                .padding([.horizontal, .bottom], PaeoniaSpacing.space12)
                .padding(.top, PaeoniaSpacing.space4)
                .background(alignment: .top) { textScrim }
            }
            .modifier(framing)
            .contentShape(shape)
        }
        .buttonStyle(.paeoniaPressableCard)
        .disabled(isLoading)
        .accessibilityLabel(loadingLabel.map { Text($0) } ?? Text(title))
        .accessibilityValue(isLoading ? Text(verbatim: "") : status)
        .accessibilityIdentifier(actionIdentifier)
    }

    private var tileStatus: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                status.fixedSize(horizontal: false, vertical: true)
            } else {
                status.lineLimit(3, reservesSpace: true)
            }
        }
        .font(needsAttention ? PaeoniaTypography.caption.weight(.semibold) : PaeoniaTypography.caption)
        .foregroundStyle(needsAttention ? .paeoniaTextPrimary : .paeoniaTextSecondary)
        .contentTransition(.opacity)
    }

    /// The picture behind the whole card, text included, the rounded shape, and the glow
    /// while content waits for this person.
    private var framing: PaeoniaIllustratedCardFraming<Artwork> {
        PaeoniaIllustratedCardFraming(shape: shape, needsAttention: needsAttention, artwork: artwork)
    }

    /// The optional header, title and status. While loading they hide, and the loading
    /// label stands in for them in VoiceOver.
    private var titleAndStatus: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            header()
            Text(title)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .accessibilityLabel(loadingLabel.map { Text($0) } ?? Text(title))
                .accessibilityAddTraits(.isHeader)
            statusLine
                .accessibilityHidden(isLoading)
        }
        .frame(maxWidth: .infinity)
        .paeoniaLoadingReveal(isLoading)
        .overlay {
            if let loadingLabel {
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel(Text(loadingLabel))
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    /// The header, title, status, button and extras, centered under
    /// the picture's centered scene.
    private var textBlock: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if dynamicTypeSize.isAccessibilitySize {
                badge()
                    .fixedSize(horizontal: false, vertical: true)
            }
            titleAndStatus

            Button {
                PaeoniaHaptics.cardOpened()
                open()
            } label: {
                // Hidden like the name and status, since the loading title is a guess.
                Text(actionTitle)
                    .paeoniaLoadingReveal(isLoading, delay: 0.16)
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

    /// The plum scrim gets darker toward the actions. The artwork contrast check
    /// uses the same values in `PaeoniaIllustratedCardLayout`.
    private var textScrim: some View {
        let shadow = Color.paeoniaBackgroundSecondary
        return LinearGradient(
            colors: [
                shadow.opacity(PaeoniaIllustratedCardLayout.shadowAtTitle),
                shadow.opacity(PaeoniaIllustratedCardLayout.shadowAtBottom),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: PaeoniaIllustratedCardLayout.blurFadeIn)
                Color.black
            }
        }
        .padding(.top, -PaeoniaIllustratedCardLayout.blurLead)
    }

    /// Emphasized text stays light so it remains readable over pink artwork.
    private var statusLine: some View {
        status
            .font(needsAttention ? PaeoniaTypography.bodyEmphasis : PaeoniaTypography.body)
            .foregroundStyle(needsAttention ? .paeoniaTextPrimary : .paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .contentTransition(.opacity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What the full card and the tile share around their content.
private struct PaeoniaIllustratedCardFraming<Artwork: View>: ViewModifier {
    let shape: RoundedRectangle
    let needsAttention: Bool
    let artwork: () -> Artwork

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) { artwork() }
            .clipShape(shape)
            .paeoniaCardSurface(in: shape, fill: Color.paeoniaBackgroundSecondary, needsAttention: needsAttention)
    }
}
