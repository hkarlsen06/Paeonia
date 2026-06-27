import SwiftUI

/// Compact entry point for today's Daily Challenge on the Us tab.
///
/// When `morphNamespace` is set, the eyebrow, the step bar, and the primary button
/// take part in the hero morph that expands this card into the answering flow.
struct DailyPromptCard: View {
    let state: DailyChallengeCardState
    var morphNamespace: Namespace.ID?
    var onAnswer: () -> Void = {}

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                HStack(alignment: .center) {
                    PaeoniaCardEyebrow(.homeDailyPromptEyebrow)
                        .dailyChallengeMorph(DailyChallengeMorph.eyebrow, in: morphNamespace)

                    Spacer(minLength: PaeoniaSpacing.space12)

                    DailyPromptProgressPill(
                        answeredCount: state.answeredCount,
                        totalCount: state.totalCount
                    )
                }

                DailyChallengeStepBar(
                    total: state.totalCount,
                    completed: state.answeredCount
                )
                .dailyChallengeMorph(DailyChallengeMorph.stepBar, in: morphNamespace)

                titleBlock

                Button(action: onAnswer) {
                    Text(actionTitle)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .disabled(!state.isActionEnabled)
                .dailyChallengeMorph(DailyChallengeMorph.primaryButton, in: morphNamespace)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: LocalizedStringResource {
        switch state.kind {
        case .loading:
            .dailyChallengeHomeLoadingTitle
        case .noChallenge:
            .dailyChallengeHomeNoChallengeTitle
        case .active:
            .dailyChallengeHomeActiveTitle
        case .complete:
            .dailyChallengeHomeCompleteTitle
        }
    }

    private var message: String? {
        switch state.kind {
        case .loading:
            nil
        case .noChallenge:
            String(localized: .dailyChallengeHomeNoChallengeMessage)
        case let .active(prompt):
            prompt
        case .complete:
            String(localized: .dailyChallengeHomeCompleteMessage)
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch state.kind {
        case .loading:
            .dailyChallengeOpenButton
        case .noChallenge:
            .dailyChallengeStartButton
        case .active, .complete:
            .dailyChallengeOpenButton
        }
    }
}

private struct DailyPromptProgressPill: View {
    let answeredCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Text(answeredCount, format: .number)
            Text(verbatim: "/")
            Text(totalCount, format: .number)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.paeoniaTextInverse)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background(.paeoniaAccentPrimary)
        .clipShape(Capsule())
    }
}

#if DEBUG
#Preview {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .active(prompt: "A small moment today"),
            answeredCount: 1,
            totalCount: 3
        )
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
