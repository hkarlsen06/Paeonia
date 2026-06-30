import SwiftUI

/// Compact entry point for today's Daily Challenge on the Us tab.
///
/// The card is the source the answering flow zooms out of; its parent marks it with
/// `.matchedTransitionSource`, so the card itself appears to grow into the full-screen
/// flow when tapped.
struct DailyPromptCard: View {
    let state: DailyChallengeCardState
    /// The partner's display name, used by the "See %@'s answers" CTA so it names the
    /// partner instead of saying "partner".
    var partnerName: String
    var prefersPartnerAnswersWhenComplete = false
    var onAnswer: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                HStack(alignment: .center) {
                    PaeoniaCardEyebrow(.homeDailyPromptEyebrow)

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

                titleBlock

                actionButton
            }
            // Crossfade the changing content when the state changes — the title and
            // button label swap via `.contentTransition(.opacity)` and the message
            // line fades through its own opacity, all in this one transaction so
            // loading → active → complete settles smoothly. Keyed on `state.kind`
            // (not a sub-expression like the partner name that changes more often,
            // which would re-trigger on every render). Instant under Reduce Motion.
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: state.kind)
        }
    }

    /// The card's action. A real call to action while there's something to do
    /// (start/open the challenge) uses the filled primary button; once the day is
    /// complete it only offers to *review* answers, so it drops to the neutral
    /// secondary style — same size and shape, so the hero morph still lines up.
    @ViewBuilder
    private var actionButton: some View {
        if isReviewAction {
            styledActionButton(PaeoniaSecondaryButtonStyle())
        } else {
            styledActionButton(PaeoniaPrimaryButtonStyle())
        }
    }

    private func styledActionButton(_ style: some ButtonStyle) -> some View {
        Button(action: onAnswer) {
            Text(actionTitle)
                .contentTransition(.opacity)
        }
        .buttonStyle(style)
        .disabled(!state.isActionEnabled)
    }

    /// A review action (neutral, not a CTA) once the day is complete — unless the
    /// partner has replies the user can still unlock by answering, which keeps the
    /// "See partner answers" button a real call to action.
    private var isReviewAction: Bool {
        guard case .complete = state.kind else { return false }
        return !showsPartnerAnswersCTA
    }

    /// Whether the complete-state button points the user at partner replies they can
    /// still unlock (vs. just reviewing answers that are all in).
    private var showsPartnerAnswersCTA: Bool {
        prefersPartnerAnswersWhenComplete && state.hasAnswerablePartnerQuestions
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            // Reserve the message line's height in every state so the card never
            // changes height when content transitions from loading to active.
            // In the loading state we render an invisible placeholder occupying
            // the same vertical space as a single caption line rather than
            // conditionally showing/hiding the line.
            Text(message ?? " ")
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                // Keep the placeholder invisible; use opacity so layout is
                // identical whether or not the real string is present.
                .opacity(message == nil ? 0 : 1)
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
        case .active:
            .dailyChallengeOpenButton
        case .complete:
            if showsPartnerAnswersCTA {
                .dailyChallengeSeePartnerAnswersButton(partnerName)
            } else {
                .dailyChallengeSeeYourAnswersButton
            }
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
#Preview("Active") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .active(prompt: "A small moment today"),
            answeredCount: 1,
            totalCount: 3
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Complete") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .complete,
            answeredCount: 3,
            totalCount: 3
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
