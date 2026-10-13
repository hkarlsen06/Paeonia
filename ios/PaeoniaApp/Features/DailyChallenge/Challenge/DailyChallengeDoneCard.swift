import SwiftUI

/// The one-row card the Questions tab shows instead of the big prompt card once the
/// user has answered today's questions. It says the user is done and what happens next,
/// and opens the answer flow to review the user's own answers. Like the prompt card, its
/// parent marks it as the source the flow zooms out of.
struct DailyChallengeDoneCard: View {
    let state: DailyChallengeCardState
    let partnerName: String
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            PaeoniaCard {
                HStack(spacing: PaeoniaSpacing.space12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                        Text(.dailyChallengeHomeCompleteTitle)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)

                        Text(followUp)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(.dailyChallengeSeeYourAnswersButton))
    }

    private var followUp: LocalizedStringResource {
        switch state.completeFollowUp {
        case .partnerQuestionsToAnswer:
            .dailyChallengeQuestionsDonePartnerQuestions(partnerName)
        case .waitingForPartner:
            .dailyChallengeQuestionsDoneWaiting(partnerName)
        case .bothAnswered:
            .dailyChallengeQuestionsDoneBothAnswered
        }
    }
}

#if DEBUG
#Preview("Waiting for partner") {
    DailyChallengeDoneCard(
        state: DailyChallengeCardState(kind: .complete, answeredCount: 2, totalCount: 2),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Partner questions waiting") {
    DailyChallengeDoneCard(
        state: DailyChallengeCardState(
            kind: .complete,
            answeredCount: 2,
            totalCount: 2,
            hasPartnerAnswersForToday: true,
            hasAnswerablePartnerQuestions: true
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
