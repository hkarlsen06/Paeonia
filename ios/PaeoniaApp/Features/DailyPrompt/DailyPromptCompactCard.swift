import SwiftUI

/// The daily question card once today's question is answered, where it is a card
/// (`DailyPromptInlineCard` is Home's map layout): a short row that leaves the
/// screen to the other cards. The envelope sits beside the title and one line about what
/// happens next, with the button below and the partner's waiting questions under it. While
/// the partner has not answered, the row opens this person's answer and has no button. The
/// envelope stays sealed until the partner's answers can be read, then it is open.
struct DailyPromptCompactCard: View {
    let state: DailyChallengeCardState
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let envelopeSize: CGFloat = 68

    var body: some View {
        PaeoniaCard { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            if waitsForPartner {
                Button(action: onAnswer) {
                    headline
                        .contentShape(Rectangle())
                }
                .buttonStyle(.paeoniaPressableCard)
                .accessibilityHint(Text(copy.actionTitle))
                .accessibilityIdentifier("home.dailyPrompt.action")
            } else {
                headline

                actionButton
            }

            LockedPartnerQuestionRows(
                state: state,
                partnerName: copy.partnerName,
                partnerPhotoAssetID: partnerPhotoAssetID,
                zoomNamespace: zoomNamespace,
                onOpen: onOpenPartnerQuestion
            )
        }
    }

    /// Nothing waits for this person until the partner answers, so the row itself opens their
    /// answer, with a chevron instead of a button that would outweigh everything below it.
    private var waitsForPartner: Bool {
        copy.isReviewAction && state.completeFollowUp == .waitingForPartner
    }

    /// The envelope beside the words. At accessibility text sizes the words get the whole
    /// width, with the envelope above them.
    private var headline: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space16))
        return layout {
            envelope
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(copy.title)
                    .font(waitsForPartner ? PaeoniaTypography.sectionTitle : PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message = copy.message {
                    Text(verbatim: message)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if waitsForPartner && !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The envelope sits at the bottom of a square, leaving room above for the letter to
    /// rise. The words center on the envelope itself, not on the empty room above it.
    /// `DailyPromptCard` draws the envelope on the spot.
    private var envelope: some View {
        let envelopeHeight = Self.envelopeSize / PaeoniaEnvelopeLayer.aspect
        return DailyPromptEnvelopeSpot(width: Self.envelopeSize)
            .frame(width: Self.envelopeSize, height: Self.envelopeSize, alignment: .bottom)
            .alignmentGuide(VerticalAlignment.center) { dimensions in
                dimensions.height - envelopeHeight / 2
            }
    }

    @ViewBuilder
    private var actionButton: some View {
        if copy.isReviewAction {
            button(PaeoniaSecondaryButtonStyle())
        } else {
            button(PaeoniaPrimaryButtonStyle())
        }
    }

    private func button(_ style: some ButtonStyle) -> some View {
        Button(action: onAnswer) {
            Text(copy.actionTitle)
        }
        .buttonStyle(style)
        .accessibilityIdentifier("home.dailyPrompt.action")
    }
}
