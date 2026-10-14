import SwiftUI

/// The one-row card the Questions tab shows instead of the big prompt card once the
/// user has answered today's questions. It says the user is done and what happens next,
/// and opens the answer flow to review the user's own answers. Like the prompt card, its
/// parent marks it as the source the flow zooms out of. The partner's questions waiting
/// for the user's answer show as locked rows under it.
struct DailyChallengeDoneCard: View {
    let state: DailyChallengeCardState
    let partnerName: String
    var onOpen: () -> Void = {}
    /// Opens the answer flow of a partner question shown as a locked row.
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                Button(action: onOpen) { summary }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text(.dailyChallengeSeeYourAnswersButton))

                LockedPartnerQuestionRows(
                    state: state,
                    partnerName: partnerName,
                    onOpen: onOpenPartnerQuestion
                )
            }
        }
    }

    private var summary: some View {
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
        .contentShape(Rectangle())
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
            hasAnswerablePartnerQuestions: true,
            lockedPartnerQuestions: [
                .init(id: UUID(), shortPrompt: "A memory that stayed"),
                .init(id: UUID(), shortPrompt: "Something small you love"),
            ],
            moreLockedPartnerQuestionCount: 2
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
