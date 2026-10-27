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

            titleAndMessage

            Button(action: onAnswer) {
                Text(copy.actionTitle)
                    .redacted(reason: copy.isLoading ? .placeholder : [])
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

    private var titleAndMessage: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(copy.title)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            ZStack(alignment: .top) {
                Text(verbatim: copy.messageOrPlaceholder)
                    .foregroundStyle(.paeoniaTextSecondary)
                if copy.isLoading {
                    // Keep the loading height so the card still glides down as it fills.
                    Text(verbatim: copy.messageOrPlaceholder)
                        .lineLimit(2, reservesSpace: true)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
            .font(PaeoniaTypography.body)
            .accessibilityHidden(copy.isLoading)
        }
        .multilineTextAlignment(.center)
        // Full width, so the lines stay centered in the geometry group while the shorter
        // question replaces the placeholder.
        .frame(maxWidth: .infinity)
        .redacted(reason: copy.isLoading ? .placeholder : [])
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
