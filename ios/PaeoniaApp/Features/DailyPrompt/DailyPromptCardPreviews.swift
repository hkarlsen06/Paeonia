#if DEBUG
import SwiftUI

private let previewLockedQuestions: [DailyChallengeCardState.LockedPartnerQuestion] = [
    .init(id: UUID(), shortPrompt: "A memory that stayed"),
    .init(id: UUID(), shortPrompt: "Something small you love"),
]

private func previewCard(
    _ state: DailyChallengeCardState,
    prefersPartnerAnswersWhenComplete: Bool = false
) -> some View {
    ScrollView {
        DailyPromptCard(
            state: state,
            partnerName: "Oda",
            prefersPartnerAnswersWhenComplete: prefersPartnerAnswersWhenComplete
        )
        .padding(PaeoniaSpacing.screenHorizontalPadding)
    }
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Loading") {
    previewCard(DailyChallengeCardState(kind: .loading))
}

#Preview("No challenge yet") {
    previewCard(DailyChallengeCardState(kind: .noChallenge))
}

#Preview("Active") {
    previewCard(
        DailyChallengeCardState(
            kind: .active(prompt: "What is a small thing I do that always makes your day better?")
        )
    )
}

#Preview("Active, partner answered") {
    previewCard(
        DailyChallengeCardState(
            kind: .active(prompt: "What is a small thing I do that always makes your day better?"),
            hasPartnerAnsweredToday: true,
            hasEarlierQuestionsToAnswer: true,
            lockedPartnerQuestions: previewLockedQuestions,
            moreLockedPartnerQuestionCount: 1
        )
    )
}

#Preview("Active, accessibility text") {
    previewCard(
        DailyChallengeCardState(
            kind: .active(prompt: "What is a small thing I do that always makes your day better?")
        )
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Complete, earlier questions waiting") {
    previewCard(
        DailyChallengeCardState(
            kind: .complete,
            hasPartnerAnsweredToday: true,
            hasEarlierQuestionsToAnswer: true,
            lockedPartnerQuestions: Array(previewLockedQuestions.prefix(1))
        ),
        prefersPartnerAnswersWhenComplete: true
    )
}

#Preview("Complete") {
    previewCard(DailyChallengeCardState(kind: .complete))
}

#Preview("Complete, accessibility text") {
    previewCard(DailyChallengeCardState(kind: .complete))
        .dynamicTypeSize(.accessibility3)
}
#endif
