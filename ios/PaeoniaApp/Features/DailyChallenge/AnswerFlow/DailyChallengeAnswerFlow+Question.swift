import SwiftUI

extension DailyChallengeAnswerFlow {
    // MARK: - Current question helpers

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
        return currentQuestion.canBeSkipped && !viewModel.isSending(currentQuestion.id)
    }

    /// True once anything is typed, picked, or staged. Skipping discards it, so Skip
    /// must not be reachable while there's an answer in progress, even one that
    /// can't be sent yet (for example text over the length limit).
    var hasDraftForCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.hasDraftContent(for: currentQuestion.id)
    }

    /// Both answers of the question the user sent are in and the partner's can be read.
    var sentQuestionIsRevealed: Bool {
        sentQuestionID.flatMap(viewModel.knownQuestion)?.hasRevealedPartnerAnswer == true
    }

    /// The server refused the answer for good while the chat showed, and it is back in
    /// the composer. Nothing will unlock, so the chat gives way to the question.
    var wasAnswerReturned: Bool {
        guard chat != nil, let questionID = sentQuestionID else { return false }
        return !viewModel.isSending(questionID)
            && viewModel.knownQuestion(questionID)?.hasOwnAnswer != true
            && viewModel.hasDraftContent(for: questionID)
    }

    /// The flow's primary button sends a new answer when one is being typed, saves
    /// an edit to an answer that can still be changed, or closes the flow.
    var isPrimaryActionSend: Bool {
        guard let currentQuestion else { return false }
        return !currentQuestion.hasOwnAnswer
            && currentQuestion.canSubmitAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True only when the user has actually changed a previously sent answer (and
    /// not blanked it). When there's no change, the button becomes Done instead.
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
        return .dailyChallengeFlowDoneButton
    }

    var isPrimaryDisabled: Bool {
        guard let currentQuestion else { return false }

        if isPrimaryActionSend {
            return !viewModel.hasDraftToSubmit(for: currentQuestion) || isSubmittingCurrent || isShufflingCurrent
        }

        if isPrimaryActionSave {
            return isSubmittingCurrent || viewModel.isDraftTextTooLong(for: currentQuestion.id)
        }

        // Done is plain navigation, always available.
        return false
    }
}
