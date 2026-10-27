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
        case .loading, .noChallenge:
            .dailyChallengeHomeNoChallengeTitle
        case .active:
            .dailyChallengeHomeActiveTitle
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
            case .earlierQuestionsToAnswer:
                String(localized: .dailyChallengeHomeCompletePartnerAnsweredMessage(partnerName))
            case .waitingForPartner:
                // Their part is still to come; say what happens next.
                String(localized: .dailyChallengeHomeCompleteWaitingMessage(partnerName))
            case .bothAnswered:
                String(localized: .dailyChallengeHomeCompleteMessage)
            }
        }
    }

    /// During loading, the localized loading label sizes the hidden placeholder.
    var messageOrPlaceholder: String {
        message ?? String(localized: .dailyChallengeHomeLoadingTitle)
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
            } else if state.completeFollowUp == .bothAnswered {
                .dailyChallengeOpenChatButton
            } else {
                .dailyChallengeSeeYourAnswersButton
            }
        }
    }

    /// Whether the complete-state button points at earlier questions the partner
    /// answered and the user can still unlock, instead of today's answers.
    var showsPartnerAnswersCTA: Bool {
        prefersPartnerAnswersWhenComplete && state.hasEarlierQuestionsToAnswer
    }

    /// Once today's question is answered the button only reviews answers, so it drops
    /// to the neutral style, unless the partner's earlier answers are waiting.
    var isReviewAction: Bool {
        state.kind == .complete && !showsPartnerAnswersCTA
    }
}
