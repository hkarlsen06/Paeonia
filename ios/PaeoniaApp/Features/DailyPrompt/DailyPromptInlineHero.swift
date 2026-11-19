import SwiftUI

extension EnvironmentValues {
    /// PROTOTYPE. True on Home's map layout, where today's question sits on the page
    /// instead of in a card.
    @Entry var dailyPromptIsInline = false
}

/// PROTOTYPE. Today's question as part of Home's page: the sealed envelope beside the
/// title and the question, then the button and the partner's waiting questions, with no
/// card around them. The envelope sits beside the words so the map above keeps its height,
/// and with it room to show both partners north up. At accessibility text sizes the words
/// need the full width, so the envelope goes back above them. `DailyPromptCard` draws the
/// envelope on `DailyPromptEnvelopeSpot`.
struct DailyPromptInlineHero: View {
    let state: DailyChallengeCardState
    let art: DailyPromptCardArt
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    private static let envelopeWidth: CGFloat = 112
    private static let stackedEnvelopeWidth: CGFloat = 132

    @Environment(\.homeMapExplorer) private var homeMapExplorer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            envelopeAndWords
                // No wider than the calendar and the drawing under them. The button and the
                // rows below keep the full width.
                .narrowsToHomeTiles()
            // The envelope and the words lie on Home's map, so a drag or a pinch on them or
            // beside them moves the map. A tap on the envelope still opens the question.
            .homeMapRows("question", homeMapExplorer)

            Button(action: onAnswer) {
                Text(copy.actionTitle)
                    .paeoniaLoadingReveal(copy.isLoading, delay: 0.16)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(copy.isLoading)
            .accessibilityIdentifier("home.dailyPrompt.action")

            LockedPartnerQuestionRows(
                state: state,
                partnerName: copy.partnerName,
                partnerPhotoAssetID: partnerPhotoAssetID,
                zoomNamespace: zoomNamespace,
                onOpen: onOpenPartnerQuestion
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var envelopeAndWords: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space16))
        return layout {
            Button(action: onAnswer) {
                DailyPromptEnvelopeSpot(width: isStacked ? Self.stackedEnvelopeWidth : Self.envelopeWidth)
            }
            .buttonStyle(.plain)
            .disabled(copy.isLoading)
            .accessibilityHidden(true)

            titleAndMessage
        }
    }

    private var titleAndMessage: some View {
        VStack(alignment: isStacked ? .center : .leading, spacing: PaeoniaSpacing.space4) {
            Text(copy.title)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .oneLineBesideEnvelope(!isStacked)
                .paeoniaLoadingReveal(copy.isLoading)
            ZStack(alignment: .top) {
                Text(verbatim: copy.messageOrPlaceholder)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .oneLineBesideEnvelope(!isStacked)
                    .paeoniaLoadingReveal(copy.isLoading, delay: 0.08)
                if copy.isLoading {
                    // Keep the loading height so the card still glides down as it fills.
                    Text(verbatim: copy.messageOrPlaceholder)
                        .lineLimit(isStacked ? 2 : 1, reservesSpace: true)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
            .font(PaeoniaTypography.body)
            .accessibilityHidden(copy.isLoading)
        }
        .multilineTextAlignment(isStacked ? .center : .leading)
        // The rest of the width, so the lines keep their place in the geometry group while
        // the shorter question replaces the placeholder.
        .frame(maxWidth: .infinity, alignment: isStacked ? .center : .leading)
        .overlay {
            if copy.isLoading {
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel(Text(.dailyChallengeHomeLoadingTitle))
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

extension View {
    /// Beside the envelope on Home's map the words keep to one line, shrinking a little
    /// before they cut off. At accessibility text sizes they sit under it and wrap.
    @ViewBuilder
    func oneLineBesideEnvelope(_ isBeside: Bool) -> some View {
        if isBeside {
            lineLimit(1).minimumScaleFactor(0.7)
        } else {
            self
        }
    }
}

/// The daily envelope with its wax seal on the tip of the flap, `width` wide. When the
/// seal breaks it lifts, turns and fades.
struct DailyPromptSealedEnvelope: View {
    let width: CGFloat
    let seal: DailyPromptCardArt.Seal
    var sealBreak: Double = 0
    var opening = DailyPromptEnvelopeOpening.closed

    var body: some View {
        let height = width / PaeoniaEnvelopeLayer.aspect
        DailyPromptEnvelope(width: width, opening: opening)
            .overlay {
                Image(seal == .pink ? .homeWaxSealPink : .homeWaxSealLavender)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width * 150 / 560)
                    .scaleEffect(1 + 0.4 * sealBreak)
                    .rotationEffect(.degrees(24 * sealBreak))
                    .offset(y: height * (0.614 - 0.5) - 10 * sealBreak)
                    .offset(x: width * (0.495 - 0.5))
                    .opacity(opening == .closed ? 1 - sealBreak : 0)
                    .accessibilityHidden(true)
            }
            .frame(width: width, height: height)
    }
}

extension EnvironmentValues {
    /// Set by `DailyPromptCard`, so its shapes' envelope spots and the one envelope it
    /// draws share a frame.
    @Entry var dailyPromptEnvelopeSpace: Namespace.ID?
}

/// Where a shape of the daily card puts its envelope, `width` wide. The spot is empty.
/// `DailyPromptCard` draws one envelope that follows the spot of the shape it shows, so
/// when the card changes shape the same envelope moves and shrinks or grows into its new
/// place instead of one envelope fading out while another fades in.
struct DailyPromptEnvelopeSpot: View {
    static let id = "dailyPromptEnvelope"

    let width: CGFloat

    @Environment(\.dailyPromptEnvelopeSpace) private var space

    var body: some View {
        let spot = Color.clear
            .frame(width: width, height: width / PaeoniaEnvelopeLayer.aspect)
            .contentShape(Rectangle())
        if let space {
            spot.matchedGeometryEffect(id: Self.id, in: space)
        } else {
            spot
        }
    }
}
