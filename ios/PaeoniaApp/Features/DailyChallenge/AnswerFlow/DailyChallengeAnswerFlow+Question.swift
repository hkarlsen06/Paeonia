import SwiftUI

extension DailyChallengeAnswerFlow {
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

    var hasDraftForCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.hasDraftContent(for: currentQuestion.id)
    }

    var wasAnswerReturned: Bool {
        guard chat != nil, let sentQuestionID else { return false }
        return !viewModel.isSending(sentQuestionID)
            && viewModel.knownQuestion(sentQuestionID)?.hasOwnAnswer != true
            && viewModel.hasDraftContent(for: sentQuestionID)
    }

    var isPrimaryDisabled: Bool {
        guard let currentQuestion else { return true }
        return !viewModel.hasDraftToSubmit(for: currentQuestion)
            || isSubmittingCurrent || isShufflingCurrent || committedAnswerHold != nil
    }
}
