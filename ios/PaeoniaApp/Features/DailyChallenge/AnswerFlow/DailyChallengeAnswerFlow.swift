import Foundation
import SwiftUI

/// The focused, full-screen answering experience for today's daily challenge.
///
/// It is presented as a full-screen cover that zooms out of the card that opened it
/// (the Us-tab prompt card or the Questions overview hero card), so the card appears to
/// grow into the screen. The body steps through one question at a time, a quiet "Skip"
/// swaps an unanswered question for a fresh one (the backend caps swaps per day), and
/// the Close button — or a drag-down — shrinks it back into the card.
struct DailyChallengeAnswerFlow: View {
    let viewModel: DailyChallengeViewModel
    var onClose: () -> Void = {}
    /// Builds the streak-restore purchase view model the completion screen uses to
    /// buy a slipped streak back in place. Called once, lazily, the first time a
    /// completion with a restorable streak appears.
    var makeStreakRestoreViewModel: @MainActor () -> StreakRestoreViewModel = {
        StreakRestoreViewModel(streak: .none, userID: nil)
    }
    /// Opens the Questions tab so the user can pick up optional partner
    /// answers after their required streak questions are finished.
    var onOpenPartnerQuestions: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var didSetInitialIndex = false
    @State private var didCelebrate = false
    /// The in-place streak-restore purchase driver, created only when a slipped
    /// streak's completion appears. Drives the completion screen's buy button and the
    /// revive-and-refill celebration once a purchase lands.
    @State private var restoreViewModel: StreakRestoreViewModel?
    @State private var committedAnswerHold: DailyAnswerStepVisualHold?
    /// A partner question stays captured while its answer sends and its unlocked
    /// exchange loads. It must not be derived from `answerFlowQuestions`: that list
    /// intentionally removes the question once the user answers, which used to swap
    /// this cover to completion before the reveal appeared.
    @State private var partnerRevealQuestion: DailyChallengeQuestion?
    @State private var isAwaitingPartnerReveal = false
    @FocusState private var isComposerFocused: Bool

    private enum Phase {
        case loading
        case answering
        case unavailable
        case complete
    }

    private var questions: [DailyChallengeQuestion] {
        viewModel.snapshot.answerFlowQuestions
    }

    private var requiredQuestions: [DailyChallengeQuestion] {
        viewModel.snapshot.ownQuestions
    }

    private var hasPartnerQuestionsToAnswer: Bool {
        viewModel.snapshot.hasAnswerablePartnerQuestions
    }

    private var phase: Phase {
        if didCelebrate { return .complete }
        if !questions.isEmpty { return .answering }
        if viewModel.isStarting || viewModel.isLoading { return .loading }
        return .unavailable
    }

    /// The streak shown on the completion celebration.
    ///
    /// Answers send local-first, so the stored streak may not yet reflect today
    /// when this screen appears. We predict today's increment from the stored
    /// streak and the couple's local date — the same rule the server applies once
    /// the answer lands — so the number is right immediately and offline.
    private var currentStreak: Int {
        StreakCelebration.celebratedCount(
            serverCurrentCount: viewModel.streak.currentCount,
            lastQualifiedDate: viewModel.streak.lastQualifiedDate,
            todayLocalDate: viewModel.snapshot.currentDayLocalDate,
            partnerContributedToday: viewModel.streak.partnerContributedToday
        )
    }

    /// Drives the answering → completion swap. A gentle celebratory bloom under
    /// motion; a plain timed cross-fade when Reduce Motion is on.
    private var celebrateAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: PaeoniaMotion.motionDefault)
            : PaeoniaMotion.celebrationReveal
    }

    /// The completion surface grows in from slightly smaller as the question fades
    /// out, so the streak screen reads as a reward arriving rather than a swap.
    /// Reduce Motion drops the scale and keeps only the cross-fade.
    private var completionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.92))
    }

    var body: some View {
        ZStack {
            if let partnerRevealQuestion {
                if isAwaitingPartnerReveal {
                    partnerRevealHoldingState(partnerRevealQuestion)
                } else {
                    DailyPartnerAnswerRevealView(
                        question: partnerRevealQuestion,
                        revealedQuestion: revealedQuestion(for: partnerRevealQuestion.id),
                        participants: viewModel.participants,
                        sending: viewModel.sendingPreview(
                            for: revealedQuestion(for: partnerRevealQuestion.id) ?? partnerRevealQuestion
                        ),
                        onDone: finishPartnerReveal
                    )
                    .transition(.opacity)
                }
            } else {
                switch phase {
                case .complete:
                    DailyChallengeCompletionView(
                        streak: currentStreak,
                        partnerName: viewModel.participants.partnerName,
                        restorableCount: viewModel.streak.isRestorable ? viewModel.streak.restorableCount : nil,
                        restoreDeadline: viewModel.streak.restoreDeadline,
                        restoreViewModel: restoreViewModel,
                        hasPartnerQuestionsToAnswer: hasPartnerQuestionsToAnswer,
                        onOpenPartnerQuestions: onOpenPartnerQuestions,
                        onDone: dismiss
                    )
                    .transition(completionTransition)
                case .loading:
                    loadingState
                case .unavailable:
                    unavailableState
                case .answering:
                    answeringState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the plum bleed under the keyboard's safe-area region too. Keyboard
        // avoidance otherwise shrinks this surface above the keyboard, so the window's
        // black showed through the keyboard's rounded top corners.
        .background { Color.paeoniaBackgroundPrimary.ignoresSafeArea() }
        .animation(celebrateAnimation, value: didCelebrate)
        .onAppear { setInitialIndexIfNeeded() }
        .onChange(of: questions.count) { _, newCount in
            setInitialIndexIfNeeded()
            // Keep the selected step valid if the list shrinks under us.
            if newCount > 0, index > newCount - 1 {
                index = newCount - 1
            }
        }
        .onChange(of: index) { _, _ in isComposerFocused = false }
        .onChange(of: wasPartnerAnswerReturned) { _, returned in
            guard returned, let questionID = partnerRevealQuestion?.id else { return }
            withAnimation(PaeoniaMotion.stateChange) {
                partnerRevealQuestion = nil
                if let returnedIndex = questions.firstIndex(where: { $0.id == questionID }) {
                    index = returnedIndex
                }
            }
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    // MARK: - States

    /// Step bar. It's the top chrome now that the eyebrow is gone, and a progress
    /// meter only — moving between questions is deliberate, via the button. Close lives
    /// in the bottom action bar, within thumb reach. The top padding gives the thin bar
    /// clearance from the safe area that the eyebrow's text height used to provide.
    private var header: some View {
        stepHeader(currentStep: currentRequiredStep)
    }

    private func stepHeader(currentStep: Int?) -> some View {
        DailyChallengeStepBar(
            total: DailyChallengeProgress.requiredOwnQuestionCount,
            completedSteps: answeredRequiredSteps,
            current: currentStep,
            height: 8,
            onSelect: requiredQuestions.isEmpty ? nil : { (step: Int) in goToRequiredStep(step) }
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
    }

    private var answeringState: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            // The header stays put while the keyboard is up. It anchors the top of the
            // screen, so the question doesn't jump when the field focuses — the whole
            // composer-and-bar cluster simply rides up above the keyboard via SwiftUI's
            // keyboard avoidance, with nothing resizing, rather than the top moving.
            header

            if let question = currentQuestion {
                DailyChallengeAnswerStep(
                    question: question,
                    viewModel: viewModel,
                    isFocused: $isComposerFocused,
                    visualHold: visualHold(for: question),
                    // The progress bar above already sets the top spacing, so the
                    // question only needs a small gap to sit grouped beneath it.
                    topPadding: PaeoniaSpacing.space4
                )
                .id(question.id)
                // Neutral fade: the user can move forward (Send) or jump to any
                // step in the bar, so a directional slide would read wrong one way.
                .transition(.opacity)
            }

            actionBar
        }
        // No explicit animation on this stack: the composer is moved only by the
        // keyboard, via SwiftUI's automatic keyboard-avoidance, which already tracks
        // the keyboard's real animation. Nothing here resizes on focus (the action bar
        // is a constant-height row), so there's no second layout change to animate —
        // and an explicit `.animation` would only re-time the keyboard's movement onto
        // a fixed curve and make it bounce.
        .dismissesKeyboardOnTap { isComposerFocused = false }
    }

    /// Holds the committed partner answer in the same challenge chrome while the
    /// unlocked snapshot arrives. The captured question and visual draft keep this
    /// surface stable even when the live question list re-sorts underneath it.
    private func partnerRevealHoldingState(_ question: DailyChallengeQuestion) -> some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            // A partner question is outside the required three, so no required step
            // should become selected just because the live list re-indexes underneath.
            stepHeader(currentStep: nil)

            DailyChallengeAnswerStep(
                question: question,
                viewModel: viewModel,
                isFocused: $isComposerFocused,
                visualHold: visualHold(for: question),
                topPadding: PaeoniaSpacing.space4
            )

            DailyChallengeAnswerActionBar(
                primaryTitle: .dailyChallengeSubmitButton,
                isPrimaryBusy: true,
                isPrimaryDisabled: true,
                onPrimary: {},
                onClose: dismiss
            )
        }
    }

    private var actionBar: some View {
        DailyChallengeAnswerActionBar(
            primaryTitle: primaryActionTitle,
            isPrimaryBusy: isSubmittingCurrent,
            isPrimaryDisabled: isPrimaryDisabled,
            isComposing: isComposerFocused,
            canSkip: canSkipCurrent,
            isSkipBusy: isShufflingCurrent,
            isSkipDisabled: isShufflingCurrent || hasDraftForCurrent,
            onPrimary: handlePrimary,
            onClose: dismiss,
            onSkip: { Task { await skipCurrent() } },
            onDone: { isComposerFocused = false }
        )
    }

    private var loadingState: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            header
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.paeoniaAccentPrimary)
            Spacer()
        }
    }

    private var unavailableState: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            header
            Spacer()
            PaeoniaEmptyStateView(
                title: .dailyChallengeHomeNoChallengeTitle,
                message: .dailyChallengeHomeNoChallengeMessage,
                systemImage: "sparkles"
            )
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            Spacer()
            // Reached when starting failed (often offline) or the couple's day ended
            // while the flow was open. Either way, starting is the next step, so it's
            // offered here instead of sending the user back to the card.
            VStack(spacing: PaeoniaSpacing.space12) {
                Button {
                    Task { await viewModel.startToday() }
                } label: {
                    Text(.dailyChallengeStartButton)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())

                Button(action: dismiss) {
                    Text(.dailyChallengeFlowClose)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
    }

    // MARK: - Current question helpers

    private var boundedIndex: Int {
        guard !questions.isEmpty else { return 0 }
        return min(max(index, 0), questions.count - 1)
    }

    private var currentQuestion: DailyChallengeQuestion? {
        guard !questions.isEmpty else { return nil }
        return questions[boundedIndex]
    }

    private var isLastStep: Bool {
        boundedIndex >= questions.count - 1
    }

    private var currentRequiredStep: Int? {
        guard let currentQuestion, currentQuestion.origin == .own else { return nil }
        return requiredQuestions.firstIndex { $0.id == currentQuestion.id }
    }

    /// The required steps the user has answered, by position. An answer that is still
    /// sending counts, because it's done from the user's side.
    private var answeredRequiredSteps: Set<Int> {
        Set(requiredQuestions.indices.filter { index in
            requiredQuestions[index].hasOwnAnswer || viewModel.isSending(requiredQuestions[index].id)
        })
    }

    private var answeredRequiredCount: Int {
        min(answeredRequiredSteps.count, DailyChallengeProgress.requiredOwnQuestionCount)
    }

    private var hasFinishedRequiredQuestions: Bool {
        answeredRequiredCount >= DailyChallengeProgress.requiredOwnQuestionCount
    }

    private var answerableIndices: [Int] {
        questions.indices.filter {
            !questions[$0].hasOwnAnswer
            && questions[$0].isAvailableToAnswer
            && !viewModel.isSending(questions[$0].id)
        }
    }

    private var answerableRequiredIndices: [Int] {
        answerableIndices.filter { questions[$0].origin == .own }
    }

    private var isSubmittingCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.submittingQuestionID == currentQuestion.id
    }

    private var isShufflingCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.isShuffling(currentQuestion)
    }

    private var canSkipCurrent: Bool {
        guard let currentQuestion else { return false }
        return currentQuestion.origin == .own
            && !currentQuestion.hasOwnAnswer
            && currentQuestion.isAvailableToAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True once anything is typed, picked, or staged. Skipping discards it, so Skip
    /// must not be reachable while there's an answer in progress, even one that
    /// can't be sent yet (for example text over the length limit).
    private var hasDraftForCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.hasDraftContent(for: currentQuestion.id)
    }

    /// The server refused the partner answer on the reveal for good, and it is back in
    /// the composer. Nothing will unlock, so the reveal gives way to the question.
    private var wasPartnerAnswerReturned: Bool {
        guard let questionID = partnerRevealQuestion?.id, !isAwaitingPartnerReveal else { return false }
        return !viewModel.isSending(questionID)
            && revealedQuestion(for: questionID)?.hasOwnAnswer != true
            && viewModel.hasDraftContent(for: questionID)
    }

    /// The flow's primary button sends a new answer when one is being typed, saves
    /// an edit to an answer that can still be changed, or just moves the user along.
    private var isPrimaryActionSend: Bool {
        guard let currentQuestion else { return false }
        return !currentQuestion.hasOwnAnswer
            && currentQuestion.canSubmitAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True only when the user has actually changed a previously sent answer (and
    /// not blanked it). When there's no change, the button becomes Next/Done instead
    /// so they can step forward without reaching for the progress bar.
    private var isPrimaryActionSave: Bool {
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

    private var primaryActionTitle: LocalizedStringResource {
        if isPrimaryActionSend { return .dailyChallengeSubmitButton }
        if isPrimaryActionSave { return .dailyChallengeFlowSaveButton }
        return isLastStep ? .dailyChallengeFlowDoneButton : .dailyChallengeFlowNextButton
    }

    private var isPrimaryDisabled: Bool {
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

    // MARK: - Actions

    private func handlePrimary() {
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

    private func dismiss() {
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

        if question.origin == .partner {
            partnerRevealQuestion = question
            isAwaitingPartnerReveal = true

            let didReveal = await viewModel.awaitAnswerReveal(for: question.id)
            if didReveal, revealedQuestion(for: question.id)?.canViewPartnerAnswer == true {
                PaeoniaHaptics.answerRevealed()
            }
            // Slow or offline: the reveal still opens, shows the answer as saved, and
            // fills in their reply when it arrives. Skipping it used to hide the
            // payoff until the user found the card again.
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

    private func revealedQuestion(for questionID: UUID) -> DailyChallengeQuestion? {
        viewModel.snapshot.questions.first { $0.id == questionID }
    }

    private func finishPartnerReveal() {
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

    private func skipCurrent() async {
        guard let question = currentQuestion else { return }
        isComposerFocused = false
        await viewModel.shuffle(question)
    }

    /// Jump to a question tapped in the progress bar. Drafts are kept, so an
    /// unanswered question reopens with your in-progress text; an answered one opens
    /// to review what you sent.
    private func goToRequiredStep(_ step: Int) {
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

    private func setInitialIndexIfNeeded() {
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

    private func visualHold(for question: DailyChallengeQuestion) -> DailyAnswerStepVisualHold? {
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
        withAnimation(celebrateAnimation) { didCelebrate = true }
    }

    private func showBanner(for notice: DailyChallengeViewModel.Notice?) {
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

#if DEBUG
#Preview {
    DailyChallengeAnswerFlowPreviewHost()
}

private struct DailyChallengeAnswerFlowPreviewHost: View {
    @State private var viewModel = DailyChallengeViewModel(service: PreviewDailyChallengeService())

    var body: some View {
        DailyChallengeAnswerFlow(viewModel: viewModel)
            .environment(PaeoniaBannerCenter())
            .preferredColorScheme(.dark)
            .task {
                await viewModel.configure(currentUserID: PreviewDailyChallengeService.userID)
            }
    }
}
#endif
