import SwiftUI

extension DailyChallengeAnswerFlow {
    // MARK: - Content

    @ViewBuilder
    func partnerRevealContent(_ question: DailyChallengeQuestion) -> some View {
        if isAwaitingPartnerReveal {
            partnerRevealHoldingState(question)
        } else {
            DailyPartnerAnswerRevealView(
                question: question,
                revealedQuestion: revealedQuestion(for: question.id),
                participants: viewModel.participants,
                sending: viewModel.sendingPreview(
                    for: revealedQuestion(for: question.id) ?? question
                ),
                onRevealed: viewModel.markPartnerAnswerSeen,
                onDone: finishPartnerReveal
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    var phaseContent: some View {
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
                milestone: celebratedMilestone,
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

    // MARK: - Earlier answer

    /// How long the note about an earlier answer stays.
    static let earlierAnswerNoteDuration: Duration = .seconds(12)

    /// The note sits under the progress bar while questions are being answered, and
    /// over the top of the other screens, such as the completion celebration.
    var showsEarlierAnswerInline: Bool {
        partnerRevealQuestion == nil && phase == .answering
    }

    /// The note, from the live copy of the question so it sees the chat open after the send.
    var earlierAnswer: DailyChallengeEarlierAnswer? {
        guard let earlierCandidate else { return nil }
        let live = viewModel.snapshot.questions.first { $0.id == earlierCandidate.id }
        return DailyChallengeEarlierAnswer(question: live ?? earlierCandidate)
    }

    func earlierAnswerNote(_ earlierAnswer: DailyChallengeEarlierAnswer) -> some View {
        DailyChallengeEarlierAnswerNote(
            earlierAnswer: earlierAnswer,
            onOpen: { onOpenQuestionChat(earlierAnswer.question) },
            onDismiss: { withAnimation(PaeoniaMotion.stateChange) { earlierCandidate = nil } }
        )
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

            if let earlierAnswer, showsEarlierAnswerInline {
                earlierAnswerNote(earlierAnswer)
                    .transition(.opacity)
            }

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
            // A partner question is outside the required questions, so no required step
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
}
