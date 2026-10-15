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
    previewCard(DailyChallengeCardState(kind: .loading, answeredCount: 0, totalCount: 2))
}

#Preview("No challenge yet") {
    previewCard(DailyChallengeCardState(kind: .noChallenge, answeredCount: 0, totalCount: 0))
}

#Preview("Active") {
    previewCard(
        DailyChallengeCardState(
            kind: .active(prompt: "What is a small thing I do that always makes your day better?"),
            answeredCount: 1,
            totalCount: 2
        )
    )
}

#Preview("Active, partner answered") {
    previewCard(
        DailyChallengeCardState(
            kind: .active(prompt: "What is a small thing I do that always makes your day better?"),
            answeredCount: 1,
            totalCount: 2,
            hasPartnerAnswersForToday: true,
            hasAnswerablePartnerQuestions: true,
            lockedPartnerQuestions: previewLockedQuestions,
            moreLockedPartnerQuestionCount: 1
        )
    )
}

#Preview("Active, accessibility text") {
    previewCard(
        DailyChallengeCardState(
            kind: .active(prompt: "What is a small thing I do that always makes your day better?"),
            answeredCount: 0,
            totalCount: 2
        )
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Complete, partner questions waiting") {
    previewCard(
        DailyChallengeCardState(
            kind: .complete,
            answeredCount: 2,
            totalCount: 2,
            hasPartnerAnswersForToday: true,
            hasAnswerablePartnerQuestions: true,
            lockedPartnerQuestions: Array(previewLockedQuestions.prefix(1))
        ),
        prefersPartnerAnswersWhenComplete: true
    )
}

#Preview("Complete") {
    previewCard(DailyChallengeCardState(kind: .complete, answeredCount: 2, totalCount: 2))
}

#Preview("Complete, accessibility text") {
    previewCard(DailyChallengeCardState(kind: .complete, answeredCount: 2, totalCount: 2))
        .dynamicTypeSize(.accessibility3)
}
#endif
