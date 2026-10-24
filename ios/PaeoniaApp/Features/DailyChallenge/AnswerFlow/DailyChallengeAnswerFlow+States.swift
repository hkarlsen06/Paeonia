import SwiftUI

extension DailyChallengeAnswerFlow {
    // MARK: - Content

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
                milestone: celebratedMilestone,
                savableCount: viewModel.streak.isSavable && !viewModel.streak.partnerContributedToday
                    ? viewModel.streak.restorableCount
                    : nil,
                savedStreak: savedStreak,
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

    /// The note sits above the question while it is answered, and over the top of the
    /// other screens, such as the completion celebration. The chat never shows it.
    var showsEarlierAnswerInline: Bool {
        revealQuestion == nil && phase == .answering
    }

    /// The note, from the live copy of the question so it sees the chat open after the send.
    var earlierAnswer: DailyChallengeEarlierAnswer? {
        guard let earlierCandidate else { return nil }
        return DailyChallengeEarlierAnswer(question: viewModel.latestQuestion(earlierCandidate))
    }

    func earlierAnswerNote(_ earlierAnswer: DailyChallengeEarlierAnswer) -> some View {
        DailyChallengeEarlierAnswerNote(
            earlierAnswer: earlierAnswer,
            onOpen: { Task { await openChat(for: earlierAnswer.question) } },
            onDismiss: { withAnimation(PaeoniaMotion.stateChange) { earlierCandidate = nil } }
        )
    }

    // MARK: - States

    private var answeringState: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if let earlierAnswer, showsEarlierAnswerInline {
                earlierAnswerNote(earlierAnswer)
                    .transition(.opacity)
            }

            if let question = currentQuestion {
                DailyChallengeAnswerStep(
                    question: question,
                    viewModel: viewModel,
                    isFocused: $isComposerFocused,
                    visualHold: visualHold(for: question)
                )
                .id(question.id)
                // A skip swaps the question in place, so it fades rather than slides.
                .transition(.opacity)
            }

            actionBar
        }
        .padding(.top, PaeoniaSpacing.space8)
        // No explicit animation on this stack: the composer is moved only by the
        // keyboard, via SwiftUI's automatic keyboard-avoidance, which already tracks
        // the keyboard's real animation. Nothing here resizes on focus (the action bar
        // is a constant-height row), so there's no second layout change to animate —
        // and an explicit `.animation` would only re-time the keyboard's movement onto
        // a fixed curve and make it bounce.
        .dismissesKeyboardOnTap { isComposerFocused = false }
    }

    /// Holds the sent answer as it was while the partner's answer unlocks and the chat
    /// loads. The captured question and visual draft keep this surface stable even when
    /// the live question list re-sorts underneath it.
    func revealHoldingState(_ question: DailyChallengeQuestion) -> some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            DailyChallengeAnswerStep(
                question: question,
                viewModel: viewModel,
                isFocused: $isComposerFocused,
                visualHold: visualHold(for: question)
            )

            DailyChallengeAnswerActionBar(
                primaryTitle: .dailyChallengeSubmitButton,
                isPrimaryBusy: true,
                isPrimaryDisabled: true,
                onPrimary: {},
                onClose: dismiss
            )
        }
        .padding(.top, PaeoniaSpacing.space8)
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
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.paeoniaAccentPrimary)
            Spacer()
        }
    }

    private var unavailableState: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
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
