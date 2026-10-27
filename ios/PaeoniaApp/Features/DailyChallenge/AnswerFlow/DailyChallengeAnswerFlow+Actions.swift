import SwiftUI

extension DailyChallengeAnswerFlow {
    func dismiss() {
        isComposerFocused = false
        onClose()
    }

    func submitCurrent() async {
        guard let question = currentQuestion,
              viewModel.submittingQuestionID == nil,
              committedAnswerHold == nil
        else { return }

        heldQuestion = question
        committedAnswerHold = DailyAnswerStepVisualHold(question: question, viewModel: viewModel)
        await viewModel.submitAnswer(for: question)

        let didAnswer = viewModel.knownQuestion(question.id)?.hasOwnAnswer == true
            || viewModel.isSending(question.id)
        guard didAnswer else {
            heldQuestion = nil
            committedAnswerHold = nil
            return
        }

        submittedAnswer = viewModel.sendingPreview(for: question)
        sentQuestionID = question.id
        await openChat(for: viewModel.latestQuestion(question), revealsPartnerAnswer: true)
    }

    /// Preparation reads only this phone. Uploads and the partner's reply can finish
    /// after the conversation opens.
    func openChat(for question: DailyChallengeQuestion, revealsPartnerAnswer: Bool = false) async {
        guard chat == nil else { return }
        isComposerFocused = false
        await viewModel.prepareChat(for: question)
        let prepared = viewModel.makeChatViewModel(question: question)
        if revealsPartnerAnswer { prepared.revealsPartnerAnswer = true }
        guard chat == nil else { return }
        withAnimation(PaeoniaMotion.stateChange) { chat = prepared }
        heldQuestion = nil
        committedAnswerHold = nil
    }

    func skipCurrent() async {
        guard let question = currentQuestion else { return }
        isComposerFocused = false
        await viewModel.shuffle(question)
    }

    func showBanner(for notice: DailyChallengeViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message(partnerName: viewModel.participants.partnerName))
            )
        )
        viewModel.dismissNotice()
    }
}
