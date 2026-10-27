import SwiftUI

extension EnvironmentValues {
    /// PROTOTYPE. True on Home's map layout, where today's question sits on the page
    /// instead of in a card.
    @Entry var dailyPromptIsInline = false
}

/// PROTOTYPE. Today's question as part of Home's page: the sealed envelope on its own,
/// then the title, the question, the button and the partner's waiting questions, centered,
/// with no card around them.
struct DailyPromptInlineHero: View {
    let state: DailyChallengeCardState
    let art: DailyPromptCardArt
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    let sealBreak: Double
    let envelopeOpening: DailyPromptEnvelopeOpening
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    private static let envelopeWidth: CGFloat = 132

    // Each part is a geometry group because the page moves while the question loads in.
    // Without one, SwiftUI draws a part's new look (enabled, unredacted) at its final
    // place at once, while only the old look slides down to it.
    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            Button(action: onAnswer) {
                DailyPromptSealedEnvelope(
                    width: Self.envelopeWidth, seal: art.seal, sealBreak: sealBreak, opening: envelopeOpening
                )
            }
            .buttonStyle(.plain)
            .disabled(copy.isLoading)
            .accessibilityHidden(true)
            .geometryGroup()

            titleAndMessage
                .geometryGroup()

            Button(action: onAnswer) {
                Text(copy.actionTitle)
                    .redacted(reason: copy.isLoading ? .placeholder : [])
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(copy.isLoading)
            .accessibilityIdentifier("home.dailyPrompt.action")
            .geometryGroup()

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

    private var titleAndMessage: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(copy.title)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: copy.message ?? "A small moment from today, just for the two of you")
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        // Full width, so the lines stay centered in the geometry group while the shorter
        // question replaces the placeholder.
        .frame(maxWidth: .infinity)
        .redacted(reason: copy.isLoading ? .placeholder : [])
    }
}

/// The daily envelope with its wax seal on the tip of the flap, `width` wide. When the
/// seal breaks it lifts, turns and fades, as on the short row.
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
            .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }
}
