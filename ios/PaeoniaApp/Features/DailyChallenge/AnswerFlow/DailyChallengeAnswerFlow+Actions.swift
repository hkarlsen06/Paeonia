import SwiftUI

extension DailyChallengeAnswerFlow {
    // MARK: - Actions

    func handlePrimary() {
        if isPrimaryActionSend {
            Task { await submitCurrent() }
        } else if isPrimaryActionSave {
            Task { await editCurrent() }
        } else {
            advanceOrFinish()
        }
    }

    /// Move to the next question, or leave the flow when this is the last one.
    private func advanceOrFinish() {
        if isLastStep {
            dismiss()
        } else {
            withAnimation(PaeoniaMotion.stateChange) { index = boundedIndex + 1 }
        }
    }

    func dismiss() {
        isComposerFocused = false
        onClose()
    }

    private func submitCurrent() async {
        // A second tap's task runs after the first one has started saving. Without
        // this guard it would see "not sent yet" and clear the first send's held
        // answer, so the composer flashed empty before moving on.
        guard
            let question = currentQuestion,
            viewModel.submittingQuestionID == nil,
            partnerRevealQuestion == nil
        else { return }

        committedAnswerHold = DailyAnswerStepVisualHold(question: question, viewModel: viewModel)
        await viewModel.submitAnswer(for: question)

        // Advance once the answer has landed on the server or — for a photo — been
        // staged to send in the background. A failure leaves the draft in place and
        // surfaces a banner instead.
        let didAnswer = (viewModel.snapshot.questions
            .first(where: { $0.id == question.id })?.hasOwnAnswer ?? false)
            || viewModel.isSending(question.id)
        guard didAnswer else {
            clearVisualHold(for: question.id)
            return
        }

        isComposerFocused = false
        withAnimation(PaeoniaMotion.stateChange) {
            earlierCandidate = question.earlierRoundCount > 0 ? question : nil
        }

        if question.origin == .partner {
            partnerRevealQuestion = question
            isAwaitingPartnerReveal = true

            let didReveal = await viewModel.awaitAnswerReveal(for: question.id)
            if didReveal, revealedQuestion(for: question.id)?.canViewPartnerAnswer == true {
                PaeoniaHaptics.answerRevealed()
            }
            // Slow or offline: the reveal still opens, shows the answer as saved, and
            // fills in their reply when it arrives.
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                isAwaitingPartnerReveal = false
            }
            releaseVisualHold(for: question.id)
        } else if hasFinishedRequiredQuestions {
            celebrate()
            releaseVisualHold(for: question.id)
        } else if let next = nextAnswerableIndex(after: boundedIndex) {
            withAnimation(PaeoniaMotion.stateChange) { index = next }
            releaseVisualHold(for: question.id)
        } else {
            celebrate()
            releaseVisualHold(for: question.id)
        }
    }

    func revealedQuestion(for questionID: UUID) -> DailyChallengeQuestion? {
        viewModel.snapshot.questions.first { $0.id == questionID }
    }

    func finishPartnerReveal() {
        guard let questionID = partnerRevealQuestion?.id else { return }
        partnerRevealQuestion = nil
        isAwaitingPartnerReveal = false
        clearVisualHold(for: questionID)
        advanceAfterPartnerAnswer()
    }

    private func advanceAfterPartnerAnswer() {
        if let next = nextAnswerableIndex(after: -1) {
            withAnimation(PaeoniaMotion.stateChange) { index = next }
        } else {
            celebrate()
        }
    }

    private func editCurrent() async {
        guard
            let question = currentQuestion,
            let kind = question.editableAnswerKind,
            viewModel.submittingQuestionID == nil
        else { return }

        switch kind {
        case .partnerChoice:
            let attempted = viewModel.partnerChoiceSelection(for: question.id)
            await viewModel.editPartnerChoiceAnswer(for: question)

            // Move on only if the save landed; a failure keeps the user here with a banner.
            let savedNow = viewModel.snapshot.answerFlowQuestions
                .first(where: { $0.id == question.id })?
                .ownAnswerDetail?.selectedUserID
            if savedNow == attempted {
                advanceOrFinish()
            }
        default:
            let attempted = viewModel.draftText(for: question.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await viewModel.editTextAnswer(for: question)
            isComposerFocused = false

            let savedNow = viewModel.snapshot.answerFlowQuestions
                .first(where: { $0.id == question.id })?
                .ownAnswerDetail?.textBody?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if savedNow == attempted {
                advanceOrFinish()
            }
        }
    }

    func skipCurrent() async {
        guard let question = currentQuestion else { return }
        isComposerFocused = false
        await viewModel.shuffle(question)
    }

    /// Jump to a question tapped in the progress bar. Drafts are kept, so an
    /// unanswered question reopens with your in-progress text; an answered one opens
    /// to review what you sent.
    func goToRequiredStep(_ step: Int) {
        guard
            step >= 0,
            step < requiredQuestions.count,
            let questionIndex = questions.firstIndex(where: { $0.id == requiredQuestions[step].id }),
            questionIndex != boundedIndex
        else { return }
        isComposerFocused = false
        withAnimation(PaeoniaMotion.stateChange) { index = questionIndex }
    }

    private func nextAnswerableIndex(after current: Int) -> Int? {
        answerableIndices.first(where: { $0 > current }) ?? answerableIndices.first
    }

    private func nextRequiredAnswerableIndex(after current: Int) -> Int? {
        answerableRequiredIndices.first(where: { $0 > current }) ?? answerableRequiredIndices.first
    }

    func setInitialIndexIfNeeded() {
        guard !didSetInitialIndex, !questions.isEmpty else { return }
        didSetInitialIndex = true
        if let first = nextRequiredAnswerableIndex(after: -1) {
            index = first
        } else if let firstRequiredQuestion = requiredQuestions.first,
                  let first = questions.firstIndex(where: { $0.id == firstRequiredQuestion.id }) {
            index = first
        } else if let first = nextAnswerableIndex(after: -1) {
            index = first
        }
    }

    func visualHold(for question: DailyChallengeQuestion) -> DailyAnswerStepVisualHold? {
        guard committedAnswerHold?.questionID == question.id else { return nil }
        return committedAnswerHold
    }

    private func clearVisualHold(for questionID: UUID) {
        guard committedAnswerHold?.questionID == questionID else { return }
        committedAnswerHold = nil
    }

    private func releaseVisualHold(for questionID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            clearVisualHold(for: questionID)
        }
    }

    /// Turns the screen over to the streak celebration. The haptics are deliberately
    /// left to `PaeoniaStreakFlame`, which owns the full crescendo — soft ticks rising
    /// with the count, then a firm payoff as the flame fills. Firing a success here too
    /// would pre-empt that build (and would be wrong for a slipped streak, which the
    /// flame keeps silent).
    private func celebrate() {
        isComposerFocused = false
        // A slipped streak's completion offers to buy the streak back in place, so
        // build the purchase driver before the completion screen renders.
        if restoreViewModel == nil, viewModel.streak.isRestorable {
            restoreViewModel = makeStreakRestoreViewModel()
        }
        if !viewModel.streak.isRestorable {
            celebratedMilestone = claimStreakMilestone(currentStreak)
        }
        withAnimation(celebrateAnimation) { didCelebrate = true }
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
