import SwiftUI

/// Compact entry point for today's Daily Challenge on the Us tab.
///
/// When `morphNamespace` is set, the eyebrow, the step bar, and the primary button
/// take part in the hero morph that expands this card into the answering flow.
struct DailyPromptCard: View {
    let state: DailyChallengeCardState
    /// The couple's streak chip. Hidden when there's nothing to show; switches to
    /// a tappable "broken" look when a lost streak can be bought back.
    var streak: StreakPillState = .hidden
    var morphNamespace: Namespace.ID?
    var prefersPartnerAnswersWhenComplete = false
    var onAnswer: () -> Void = {}
    /// Called when the user taps the chip while a restore is offered.
    var onTapStreak: (() -> Void)?

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                HStack(alignment: .center) {
                    PaeoniaCardEyebrow(.homeDailyPromptEyebrow)
                        .dailyChallengeMorph(DailyChallengeMorph.eyebrow, in: morphNamespace)

                    Spacer(minLength: PaeoniaSpacing.space12)

                    HStack(spacing: PaeoniaSpacing.space8) {
                        if streak.isVisible {
                            DailyPromptStreakPill(state: streak, onTap: onTapStreak)
                        }

                        DailyPromptProgressPill(
                            answeredCount: state.answeredCount,
                            totalCount: state.totalCount
                        )
                    }
                }

                DailyChallengeStepBar(
                    total: state.totalCount,
                    completed: state.answeredCount
                )
                .dailyChallengeMorph(DailyChallengeMorph.stepBar, in: morphNamespace)

                titleBlock

                actionButton
            }
        }
        // The collapsed anchor for the surface morph: an invisible match-frame source
        // pinned to the card, so the flow's growing surface knows where to expand from
        // and shrink back to. Held only while the card owns the morph ids (collapsed /
        // closing on the active tab); released while the flow is expanded.
        .background {
            Color.clear
                .dailyChallengeMorph(DailyChallengeMorph.surface, in: morphNamespace)
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
        }
        .buttonStyle(style)
        .disabled(!state.isActionEnabled)
        .dailyChallengeMorph(DailyChallengeMorph.primaryButton, in: morphNamespace)
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
        case .active:
            .dailyChallengeOpenButton
        case .complete:
            if showsPartnerAnswersCTA {
                .dailyChallengeSeePartnerAnswersButton
            } else {
                .dailyChallengeSeeYourAnswersButton
            }
        }
    }
}

/// What the streak chip should show: the live count normally, or a tappable
/// "broken" chip advertising the lost streak you can buy back.
struct StreakPillState: Equatable {
    var count: Int
    var isRestorable: Bool
    var restorableCount: Int

    static let hidden = StreakPillState(count: 0, isRestorable: false, restorableCount: 0)

    init(count: Int, isRestorable: Bool, restorableCount: Int) {
        self.count = count
        self.isRestorable = isRestorable
        self.restorableCount = restorableCount
    }

    init(_ streak: CoupleStreak) {
        count = streak.currentCount
        isRestorable = streak.isRestorable
        restorableCount = streak.restorableCount
    }

    /// The number on the chip: the lost streak while a restore is offered (so the
    /// chip advertises what you'd get back), otherwise the live count.
    var displayCount: Int { isRestorable ? restorableCount : count }

    /// Show the chip only when there's a streak to celebrate or a restore to offer.
    var isVisible: Bool { displayCount >= 1 }
}

/// A compact flame chip showing how many days the couple has kept their streak.
/// Uses the same brand flame as the completion celebration so the two read as one
/// idea at different sizes. When the streak has slipped, it dims and becomes a
/// button that opens the restore offer.
private struct DailyPromptStreakPill: View {
    let state: StreakPillState
    var onTap: (() -> Void)?

    var body: some View {
        if state.isRestorable, let onTap {
            Button(action: onTap) { pill }
                .buttonStyle(.plain)
        } else {
            pill
        }
    }

    private var pill: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            FlameShape()
                .fill(flameStyle)
                .frame(width: 11, height: 14)

            Text(state.displayCount, format: .number)
                .monospacedDigit()
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(state.isRestorable ? .paeoniaTextSecondary : .paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Capsule())
        .overlay {
            if state.isRestorable {
                Capsule()
                    .stroke(.paeoniaAccentPrimary.opacity(0.5), lineWidth: PaeoniaRadius.strokeDefault)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityAddTraits(state.isRestorable ? .isButton : [])
    }

    private var flameStyle: LinearGradient {
        if state.isRestorable {
            return LinearGradient(
                colors: [.paeoniaTextSecondary.opacity(0.6), .paeoniaSurfacePressed],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [.paeoniaAccentPrimary, .paeoniaInkGold],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var accessibilityLabel: String {
        let base = "\(state.displayCount) \(String(localized: .homeStreakLabel))"
        guard state.isRestorable else { return base }
        return "\(base), \(String(localized: .streakRestoreBrokenAction))"
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
#Preview("Active streak") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .active(prompt: "A small moment today"),
            answeredCount: 1,
            totalCount: 3
        ),
        streak: StreakPillState(count: 12, isRestorable: false, restorableCount: 0)
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Streak slipped") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .active(prompt: "A small moment today"),
            answeredCount: 1,
            totalCount: 3
        ),
        streak: StreakPillState(count: 1, isRestorable: true, restorableCount: 30),
        onTapStreak: {}
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
