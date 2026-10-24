import SwiftUI

extension DailyChallengeAnswerFlow {
    // MARK: - Actions

    func handlePrimary() {
        if isPrimaryActionSend {
            Task { await submitCurrent() }
        } else if isPrimaryActionSave {
            Task { await editCurrent() }
        } else {
            dismiss()
        }
    }

    func dismiss() {
        isComposerFocused = false
        onClose()
    }

    private func submitCurrent() async {
        // A second tap's task runs after the first one has started saving. Without
        // this guard it would see "not sent yet" and clear the first send's held
        // answer, so the composer flashed empty.
        guard
            let question = currentQuestion,
            viewModel.submittingQuestionID == nil,
            revealQuestion == nil
        else { return }

        committedAnswerHold = DailyAnswerStepVisualHold(question: question, viewModel: viewModel)
        await viewModel.submitAnswer(for: question)

        // Move on once the answer has landed on the server or — for a photo — been
        // staged to send in the background. A failure leaves the draft in place and
        // surfaces a banner instead.
        let didAnswer = (viewModel.knownQuestion(question.id)?.hasOwnAnswer ?? false)
            || viewModel.isSending(question.id)
        guard didAnswer else {
            clearVisualHold(for: question.id)
            return
        }

        isComposerFocused = false
        sentQuestionID = question.id
        withAnimation(PaeoniaMotion.stateChange) {
            earlierCandidate = question.earlierRoundCount > 0 ? question : nil
        }

        // The partner's answer may have reached the phone while the user was writing.
        if question.hasPartnerAnswer || viewModel.knownQuestion(question.id)?.hasPartnerAnswer == true {
            // The partner answered first, so this answer unlocks theirs. The composer
            // holds as it was for a moment, so a quick reply turns over in one step.
            revealQuestion = question
            isAwaitingReveal = true
            _ = await viewModel.awaitAnswerReveal(for: question.id)
            // Slow or offline: the reveal still opens, shows the answer as saved, and
            // fills in their reply when it arrives.
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                isAwaitingReveal = false
            }
        } else {
            // A partner answer that lands with this one turns the screen to the reveal
            // (`sentQuestionIsRevealed`).
            celebrate()
        }
        releaseVisualHold(for: question.id)
    }

    /// Closes the flow and opens the revealed question's chat.
    func openRevealedChat() {
        guard let revealQuestion else { return }
        isComposerFocused = false
        onOpenQuestionChat(viewModel.latestQuestion(revealQuestion))
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

            // Close only if the save landed; a failure keeps the user here with a banner.
            if viewModel.knownQuestion(question.id)?.ownAnswerDetail?.selectedUserID == attempted {
                dismiss()
            }
        default:
            let attempted = viewModel.draftText(for: question.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await viewModel.editTextAnswer(for: question)
            isComposerFocused = false

            let savedNow = viewModel.knownQuestion(question.id)?
                .ownAnswerDetail?.textBody?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if savedNow == attempted {
                dismiss()
            }
        }
    }

    func skipCurrent() async {
        guard let question = currentQuestion else { return }
        isComposerFocused = false
        await viewModel.shuffle(question)
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
        let streak = viewModel.streak
        if restoreViewModel == nil, streak.isRestorable {
            restoreViewModel = makeStreakRestoreViewModel()
        }
        if streak.isSavable, streak.partnerContributedToday, let today = viewModel.snapshot.currentDayLocalDate {
            // The partner already showed up today, so this answer brings the broken streak back.
            savedStreak = claimStreakSave(today, currentStreak)
        } else if !streak.isRestorable {
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
