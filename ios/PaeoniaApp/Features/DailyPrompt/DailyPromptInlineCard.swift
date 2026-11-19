import SwiftUI

extension EnvironmentValues {
    /// PROTOTYPE. True on Home's map layout, where today's question sits on the page
    /// instead of in a card.
    @Entry var dailyPromptIsInline = false
}

/// PROTOTYPE. Today's question as part of Home's page, with no card around it: the envelope
/// beside the title and one line, then the button and the partner's waiting questions. The
/// envelope sits beside the words so the map above keeps its height, and with it room to
/// show both partners north up. At accessibility text sizes the words need the full width,
/// so the envelope goes above them.
///
/// It is one view for both shapes. Once today's question is answered the envelope shrinks,
/// the words blur from the old to the new in place, and the button changes color, instead
/// of one layout fading into another. While the partner has not answered,
/// the row opens this person's answer and has no button. `DailyPromptCard` draws the
/// envelope on `DailyPromptEnvelopeSpot`.
struct DailyPromptInlineCard: View {
    let state: DailyChallengeCardState
    let art: DailyPromptCardArt
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    private static let envelopeWidth: CGFloat = 112
    private static let stackedEnvelopeWidth: CGFloat = 132
    private static let compactEnvelopeWidth: CGFloat = 68

    @Environment(\.homeMapExplorer) private var homeMapExplorer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isCompact: Bool { art.shape == .compact }

    /// Nothing waits for this person until the partner answers, so the row itself opens their
    /// answer, with a chevron instead of a button that would outweigh everything below it.
    private var waitsForPartner: Bool {
        isCompact && copy.isReviewAction && state.completeFollowUp == .waitingForPartner
    }

    /// The picture card's words sit centered under the envelope at accessibility sizes.
    private var centersWords: Bool { isStacked && !isCompact }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            headline
                // No wider than the calendar and the drawing under them. The button and the
                // rows below keep the full width.
                .narrowsToHomeTiles()
                // The row lies on Home's map, so a drag or a pinch on it or beside it moves
                // the map. A tap still opens the question.
                .homeMapRows("question", homeMapExplorer)

            if !waitsForPartner {
                Button(action: onAnswer) {
                    // A container that stays, so only the words change and not the button.
                    ZStack {
                        Text(copy.actionTitle)
                            .paeoniaLoadingReveal(copy.isLoading, delay: 0.16)
                            .changesWords(String(localized: copy.actionTitle))
                    }
                }
                .buttonStyle(PaeoniaProminenceButtonStyle(isProminent: !isCompact || !copy.isReviewAction))
                .disabled(copy.isLoading)
                .accessibilityIdentifier("home.dailyPrompt.action")
            }

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

    /// The whole row opens the question. Only the short row waiting for the partner is a
    /// button to VoiceOver, since otherwise the button under it does the same.
    private var headline: some View {
        Button(action: onAnswer) {
            envelopeAndWords
                .contentShape(Rectangle())
        }
        .buttonStyle(.paeoniaPressableCard)
        .disabled(copy.isLoading)
        .accessibilityRemoveTraits(waitsForPartner ? [] : .isButton)
        .accessibilityHint(waitsForPartner ? Text(copy.actionTitle) : Text(verbatim: ""))
        .accessibilityIdentifier(waitsForPartner ? "home.dailyPrompt.action" : "home.dailyPrompt.question")
    }

    private var envelopeAndWords: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: centersWords ? .center : .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space16))
        return layout {
            envelope
            words
            if waitsForPartner && !isStacked {
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// On the short row the envelope sits at the bottom of a square, leaving room above for
    /// the letter to rise. The words center on the envelope itself, not on the room above it.
    private var envelope: some View {
        let width = isCompact ? Self.compactEnvelopeWidth : isStacked ? Self.stackedEnvelopeWidth : Self.envelopeWidth
        let height = width / PaeoniaEnvelopeLayer.aspect
        return DailyPromptEnvelopeSpot(width: width)
            .frame(width: width, height: isCompact ? width : height, alignment: .bottom)
            .alignmentGuide(VerticalAlignment.center) { dimensions in
                dimensions.height - height / 2
            }
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: centersWords ? .center : .leading, spacing: PaeoniaSpacing.space4) {
            Text(copy.title)
                .font(titleFont)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .oneLineBesideEnvelope(!isStacked)
                .paeoniaLoadingReveal(copy.isLoading)
                .changesWords(String(localized: copy.title))
            if let message = isCompact ? copy.message : copy.messageOrPlaceholder {
                ZStack(alignment: .top) {
                    Text(verbatim: message)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .oneLineBesideEnvelope(!isStacked)
                        .paeoniaLoadingReveal(copy.isLoading, delay: 0.08)
                        .changesWords(message)
                    if copy.isLoading {
                        // Keep the loading height so the card still glides down as it fills.
                        Text(verbatim: message)
                            .lineLimit(isStacked ? 2 : 1, reservesSpace: true)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
                .font(isCompact ? PaeoniaTypography.caption : PaeoniaTypography.body)
                .accessibilityHidden(copy.isLoading)
            }
        }
        .multilineTextAlignment(centersWords ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        // The rest of the width, so the lines keep their place in the geometry group while
        // the shorter question replaces the placeholder.
        .frame(maxWidth: .infinity, alignment: centersWords ? .center : .leading)
        .overlay {
            if copy.isLoading {
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel(Text(.dailyChallengeHomeLoadingTitle))
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var titleFont: Font {
        guard isCompact else { return PaeoniaTypography.heroTitle }
        return waitsForPartner ? PaeoniaTypography.sectionTitle : PaeoniaTypography.title
    }
}

private extension View {
    /// New words blur in where the old ones blur out, instead of the two crossfading on top
    /// of each other.
    func changesWords(_ words: String) -> some View {
        transition(.blurReplace).id(words)
    }

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
