import SwiftUI

extension DailyChallengeAnswerFlow {
    @ViewBuilder
    var phaseContent: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.paeoniaAccentPrimary)
        case .unavailable:
            unavailableState
        case .answering:
            answeringState
        }
    }

    private var answeringState: some View {
        VStack(spacing: 0) {
            DailyAnswerFlowHeader(
                question: currentQuestion,
                participants: viewModel.participants,
                onClose: dismiss,
                canSkip: canSkipCurrent,
                isSkipDisabled: hasDraftForCurrent || isSubmittingCurrent,
                isSkipping: isShufflingCurrent,
                onSkip: { Task { await skipCurrent() } }
            )

            // The two questions overlap while one leaves and the next arrives.
            ZStack {
                if let question = shownQuestion {
                    DailyChallengeAnswerStep(
                        question: question,
                        viewModel: viewModel,
                        isFocused: $isComposerFocused,
                        visualHold: committedAnswerHold,
                        isSubmitting: isSubmittingCurrent || committedAnswerHold != nil,
                        isSubmitDisabled: isPrimaryDisabled,
                        onSubmit: { Task { await submitCurrent() } }
                    )
                    .id(question.id)
                    .allowsHitTesting(committedAnswerHold == nil)
                    .transition(questionSwap)
                }
            }
        }
        .padding(.top, PaeoniaSpacing.space8)
        // A skipped question drifts up and away as the new one rises into its place.
        .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: shownQuestion?.id)
    }

    private var shownQuestion: DailyChallengeQuestion? {
        heldQuestion ?? currentQuestion
    }

    /// The old question clears quickly, so the two prompts barely overlap.
    private var questionSwap: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: PaeoniaSpacing.space12))
                .animation(PaeoniaMotion.meaningfulMoment.delay(PaeoniaMotion.motionFast / 2)),
            removal: .opacity.combined(with: .offset(y: -PaeoniaSpacing.space12))
                .animation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast))
        )
    }

    private var unavailableState: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Spacer()
            PaeoniaEmptyStateView(
                title: .dailyChallengeHomeNoChallengeTitle,
                message: .dailyChallengeHomeNoChallengeMessage,
                systemImage: "sparkles"
            )
            Spacer()
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
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
    }
}
