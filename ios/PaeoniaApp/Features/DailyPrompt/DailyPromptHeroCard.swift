import SwiftUI

/// The daily question card while there is something to do, and while the questions load.
/// It is a game hub card with a sealed envelope as its picture: the title, today's
/// question, the main button, and the partner's waiting questions sit under the picture.
/// The step count floats at the top of the picture. The card glows while a question waits.
struct DailyPromptHeroCard: View {
    let state: DailyChallengeCardState
    let art: DailyPromptCardArt
    let copy: DailyPromptCardCopy
    let partnerPhotoAssetID: UUID?
    /// How far the seal has broken, from 0 to 1.
    let sealBreak: Double
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void
    var onOpenPartnerQuestion: (UUID) -> Void

    var body: some View {
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
            DailyPromptHeroArtwork(seal: art.seal, sealBreak: sealBreak)
        } badge: {
            if art.showsProgressBadge {
                progressBadge
            }
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

    /// The question. While loading it is a stand-in that is never readable (redacted), so
    /// it is not localized. It is two lines long, like most questions.
    private var status: Text {
        Text(verbatim: copy.message ?? "A small moment from today, just for the two of you")
    }

    /// "1 of 2 answered" with the step bar, in a capsule over the picture.
    private var progressBadge: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            DailyChallengeStepBar(total: state.totalCount, completed: state.answeredCount)
                .frame(width: 36)
                .accessibilityHidden(true)
            Text(.dailyChallengeHomeProgressBadge(state.answeredCount, state.totalCount))
                .font(PaeoniaTypography.caption.weight(.semibold))
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .gameCapsuleStyle()
    }
}
