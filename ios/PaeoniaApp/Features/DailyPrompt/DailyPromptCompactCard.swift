import SwiftUI

/// The daily question card once today's questions are done: a short row that leaves the
/// screen to the other cards. The open envelope sits beside the title and one line about
/// what happens next, with the button below and the partner's waiting questions under it.
struct DailyPromptCompactCard: View {
    let state: DailyChallengeCardState
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    /// The envelope pops open, for a card that just shrank from the picture card.
    let envelopePopsOpen: Bool
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var envelopeIsOpen = false

    private static let envelopeSize: CGFloat = 68

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                headline

                actionButton

                LockedPartnerQuestionRows(
                    state: state,
                    partnerName: copy.partnerName,
                    partnerPhotoAssetID: partnerPhotoAssetID,
                    zoomNamespace: zoomNamespace,
                    onOpen: onOpenPartnerQuestion
                )
            }
        }
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
                    .font(PaeoniaTypography.title)
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
        }
    }

    private var envelope: some View {
        let isShut = envelopePopsOpen && !envelopeIsOpen
        return Image(.homeEnvelopeOpen)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .frame(width: Self.envelopeSize, height: Self.envelopeSize)
            .scaleEffect(isShut ? 0.5 : 1)
            .rotationEffect(.degrees(isShut ? -12 : 0))
            .opacity(isShut ? 0 : 1)
            .onAppear {
                guard envelopePopsOpen else { return }
                withAnimation(.spring(duration: PaeoniaMotion.motionSlow, bounce: 0.4).delay(0.12)) {
                    envelopeIsOpen = true
                }
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
