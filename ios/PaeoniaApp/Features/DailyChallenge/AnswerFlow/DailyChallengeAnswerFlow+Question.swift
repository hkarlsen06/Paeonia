import SwiftUI

extension DailyChallengeAnswerFlow {
    // MARK: - Current question helpers

    var boundedIndex: Int {
        guard !questions.isEmpty else { return 0 }
        return min(max(index, 0), questions.count - 1)
    }

    var currentQuestion: DailyChallengeQuestion? {
        guard !questions.isEmpty else { return nil }
        return questions[boundedIndex]
    }

    var isLastStep: Bool {
        boundedIndex >= questions.count - 1
    }

    var currentRequiredStep: Int? {
        guard let currentQuestion, currentQuestion.origin == .own else { return nil }
        return requiredQuestions.firstIndex { $0.id == currentQuestion.id }
    }

    /// The required steps the user has answered, by position. An answer that is still
    /// sending counts, because it's done from the user's side.
    var answeredRequiredSteps: Set<Int> {
        Set(requiredQuestions.indices.filter { index in
            requiredQuestions[index].hasOwnAnswer || viewModel.isSending(requiredQuestions[index].id)
        })
    }

    private var answeredRequiredCount: Int {
        min(answeredRequiredSteps.count, DailyChallengeProgress.requiredOwnQuestionCount)
    }

    var hasFinishedRequiredQuestions: Bool {
        answeredRequiredCount >= DailyChallengeProgress.requiredOwnQuestionCount
    }

    var answerableIndices: [Int] {
        questions.indices.filter {
            !questions[$0].hasOwnAnswer
            && questions[$0].isAvailableToAnswer
            && !viewModel.isSending(questions[$0].id)
        }
    }

    var answerableRequiredIndices: [Int] {
        answerableIndices.filter { questions[$0].origin == .own }
    }

    var isSubmittingCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.submittingQuestionID == currentQuestion.id
    }

    var isShufflingCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.isShuffling(currentQuestion)
    }

    var canSkipCurrent: Bool {
        guard let currentQuestion else { return false }
        return currentQuestion.origin == .own
            && !currentQuestion.hasOwnAnswer
            && currentQuestion.isAvailableToAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True once anything is typed, picked, or staged. Skipping discards it, so Skip
    /// must not be reachable while there's an answer in progress, even one that
    /// can't be sent yet (for example text over the length limit).
    var hasDraftForCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.hasDraftContent(for: currentQuestion.id)
    }

    /// The server refused the partner answer on the reveal for good, and it is back in
    /// the composer. Nothing will unlock, so the reveal gives way to the question.
    var wasPartnerAnswerReturned: Bool {
        guard let questionID = partnerRevealQuestion?.id, !isAwaitingPartnerReveal else { return false }
        return !viewModel.isSending(questionID)
            && revealedQuestion(for: questionID)?.hasOwnAnswer != true
            && viewModel.hasDraftContent(for: questionID)
    }

    /// The flow's primary button sends a new answer when one is being typed, saves
    /// an edit to an answer that can still be changed, or just moves the user along.
    var isPrimaryActionSend: Bool {
        guard let currentQuestion else { return false }
        return !currentQuestion.hasOwnAnswer
            && currentQuestion.canSubmitAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True only when the user has actually changed a previously sent answer (and
    /// not blanked it). When there's no change, the button becomes Next/Done instead
    /// so they can step forward without reaching for the progress bar.
    var isPrimaryActionSave: Bool {
        guard let currentQuestion, let kind = currentQuestion.editableAnswerKind else { return false }
        switch kind {
        case .partnerChoice:
            guard let draft = viewModel.partnerChoiceSelection(for: currentQuestion.id) else { return false }
            return draft != currentQuestion.ownAnswerDetail?.selectedUserID
        default:
            let draft = viewModel.draftText(for: currentQuestion.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = (currentQuestion.ownAnswerDetail?.textBody ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !draft.isEmpty && draft != saved
        }
    }

    var primaryActionTitle: LocalizedStringResource {
        if isPrimaryActionSend { return .dailyChallengeSubmitButton }
        if isPrimaryActionSave { return .dailyChallengeFlowSaveButton }
        return isLastStep ? .dailyChallengeFlowDoneButton : .dailyChallengeFlowNextButton
    }

    var isPrimaryDisabled: Bool {
        guard let currentQuestion else { return false }

        if isPrimaryActionSend {
            return !viewModel.hasDraftToSubmit(for: currentQuestion) || isSubmittingCurrent || isShufflingCurrent
        }

        if isPrimaryActionSave {
            return isSubmittingCurrent || viewModel.isDraftTextTooLong(for: currentQuestion.id)
        }

        // Next / Done is plain navigation, always available.
        return false
    }
}
