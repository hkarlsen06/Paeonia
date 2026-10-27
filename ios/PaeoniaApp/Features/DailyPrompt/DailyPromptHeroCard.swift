import SwiftUI

/// The daily question card while there is something to do, and while the question loads.
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

    @Environment(\.dailyPromptIsInline) private var isInline

    var body: some View {
        if isInline {
            DailyPromptInlineHero(
                state: state,
                art: art,
                copy: copy,
                partnerPhotoAssetID: partnerPhotoAssetID,
                sealBreak: sealBreak,
                envelopeOpening: envelopeOpening,
                zoomNamespace: zoomNamespace,
                onAnswer: onAnswer,
                onOpenPartnerQuestion: onOpenPartnerQuestion
            )
        } else {
            card
        }
    }

    private var card: some View {
        GameHubCardFrame(
            name: copy.title,
            status: status,
            actionTitle: copy.actionTitle,
            isYourTurn: art.glows,
            context: nil,
            actionIdentifier: "home.dailyPrompt.action",
            open: onAnswer,
            loadingLabel: copy.isLoading ? .dailyChallengeHomeLoadingTitle : nil
        ) {
            DailyPromptHeroArtwork(seal: art.seal, sealBreak: sealBreak, opening: envelopeOpening)
        } badge: {
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
