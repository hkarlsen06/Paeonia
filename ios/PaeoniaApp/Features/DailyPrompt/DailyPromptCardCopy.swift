import Foundation

/// The words on the daily question card, shared by the picture card and the short row.
struct DailyPromptCardCopy {
    let state: DailyChallengeCardState
    /// The partner's display name, used by the "See %@'s answers" button.
    let partnerName: String
    let prefersPartnerAnswersWhenComplete: Bool

    var isLoading: Bool {
        state.kind == .loading
    }

    var title: LocalizedStringResource {
        switch state.kind {
        case .loading, .active:
            .dailyChallengeHomeActiveTitle
        case .noChallenge:
            .dailyChallengeHomeNoChallengeTitle
        case .complete:
            .dailyChallengeHomeCompleteTitle
        }
    }

    /// The question while it is active, otherwise one line about what happens next.
    /// Nil while loading.
    var message: String? {
        switch state.kind {
        case .loading:
            nil
        case .noChallenge:
            String(localized: .dailyChallengeHomeNoChallengeMessage)
        case let .active(prompt):
            prompt
        case .complete:
            switch state.completeFollowUp {
            case .partnerQuestionsToAnswer:
                String(localized: .dailyChallengeHomeCompletePartnerAnsweredMessage(partnerName))
            case .waitingForPartner:
                // Their part is still to come; say what happens next.
                String(localized: .dailyChallengeHomeCompleteWaitingMessage(partnerName))
            case .bothAnswered:
                String(localized: .dailyChallengeHomeCompleteMessage)
            }
        }
    }

    var actionTitle: LocalizedStringResource {
        switch state.kind {
        case .loading, .active:
            .dailyChallengeOpenButton
        case .noChallenge:
            .dailyChallengeStartButton
        case .complete:
            if showsPartnerAnswersCTA {
                .dailyChallengeSeePartnerAnswersButton(partnerName)
            } else {
                .dailyChallengeSeeYourAnswersButton
            }
        }
    }

    /// Whether the complete-state button points at partner replies the user can still
    /// unlock, instead of only reviewing answers that are all in.
    var showsPartnerAnswersCTA: Bool {
        prefersPartnerAnswersWhenComplete && state.hasAnswerablePartnerQuestions
    }

    /// Once the day is complete the button only reviews answers, so it drops to the
    /// neutral style, unless the partner's replies are waiting.
    var isReviewAction: Bool {
        state.kind == .complete && !showsPartnerAnswersCTA
    }
}
