import SwiftUI

/// The daily question card while there is something to do, and while the question loads,
/// where it is a card (`DailyPromptInlineCard` is Home's map layout).
/// It is a game hub card with a sealed envelope as its picture: the title, today's
/// question, the main button, and the partner's waiting questions from earlier days sit
/// under the picture. The card glows while a question waits.
struct DailyPromptHeroCard: View {
    let state: DailyChallengeCardState
    let art: DailyPromptCardArt
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    /// How far the seal has broken, from 0 to 1.
    let sealBreak: Double
    /// How far the envelope has opened after the seal broke.
    var envelopeOpening = DailyPromptEnvelopeOpening.closed
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    var body: some View {
        PaeoniaIllustratedCard(
            title: copy.title,
            status: status,
            actionTitle: copy.actionTitle,
            needsAttention: art.glows,
            actionIdentifier: "home.dailyPrompt.action",
            open: onAnswer,
            loadingLabel: copy.isLoading ? .dailyChallengeHomeLoadingTitle : nil
        ) {
            DailyPromptHeroArtwork(seal: art.seal, sealBreak: sealBreak, opening: envelopeOpening)
        } badge: {
            EmptyView()
        } header: {
            EmptyView()
        } extras: {
            LockedPartnerQuestionRows(
                state: state,
                partnerName: copy.partnerName,
                partnerPhotoAssetID: partnerPhotoAssetID,
                zoomNamespace: zoomNamespace,
                onOpen: onOpenPartnerQuestion
            )
        }
    }

    /// The question, or a localized stand-in sized for the loading placeholder.
    private var status: Text {
        Text(verbatim: copy.messageOrPlaceholder)
    }

}
