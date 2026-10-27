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

            if let question = heldQuestion ?? currentQuestion {
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
            }
        }
        .padding(.top, PaeoniaSpacing.space8)
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
