import SwiftUI

/// Compact entry point for today's Daily Challenge on the Home tab.
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
    /// Set on Home so a tapped locked row is the source its answer flow zooms out of.
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void = {}
    /// Opens the answer flow of a partner question shown as a locked row.
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                PaeoniaCardEyebrow(.homeDailyPromptEyebrow)

                DailyChallengeStepBar(
                    total: state.totalCount,
                    completed: state.answeredCount
                )
                .accessibilityHidden(isLoading)

                titleBlock

                actionButton

                LockedPartnerQuestionRows(
                    state: state,
                    partnerName: partnerName,
                    zoomNamespace: zoomNamespace,
                    onOpen: onOpenPartnerQuestion
                )
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

    private var isLoading: Bool {
        if case .loading = state.kind { true } else { false }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            // While loading, the title and message render as skeleton bars sized like
            // the active card, so a fast load doesn't flash "Loading…" text first.
            Group {
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityLabel(isLoading ? Text(.dailyChallengeHomeLoadingTitle) : Text(title))

                // The stand-in is never readable (redacted), so it isn't localized.
                Text(message ?? "A small moment from today")
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityHidden(isLoading)
            }
            .redacted(reason: isLoading ? .placeholder : [])
        }
    }

    private var title: LocalizedStringResource {
        switch state.kind {
        case .loading, .active:
            .dailyChallengeHomeActiveTitle
        case .noChallenge:
            .dailyChallengeHomeNoChallengeTitle
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
            if state.hasAnswerablePartnerQuestions {
                String(localized: .dailyChallengeHomeCompletePartnerAnsweredMessage(partnerName))
            } else if !state.hasPartnerAnswersForToday {
                // Their part is still to come; say what happens next.
                String(localized: .dailyChallengeHomeCompleteWaitingMessage(partnerName))
            } else {
                String(localized: .dailyChallengeHomeCompleteMessage)
            }
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

#if DEBUG
#Preview("Loading") {
    DailyPromptCard(
        state: DailyChallengeCardState(kind: .loading, answeredCount: 0, totalCount: 2),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Active") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .active(prompt: "A small moment today"),
            answeredCount: 1,
            totalCount: 2
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Active · partner answered") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .active(prompt: "A small moment today"),
            answeredCount: 1,
            totalCount: 2,
            hasPartnerAnswersForToday: true,
            hasAnswerablePartnerQuestions: true,
            lockedPartnerQuestions: [
                .init(id: UUID(), shortPrompt: "A memory that stayed"),
                .init(id: UUID(), shortPrompt: "Something small you love"),
            ],
            moreLockedPartnerQuestionCount: 1
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Complete · partner questions waiting") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .complete,
            answeredCount: 2,
            totalCount: 2,
            hasPartnerAnswersForToday: true,
            hasAnswerablePartnerQuestions: true,
            lockedPartnerQuestions: [.init(id: UUID(), shortPrompt: "A memory that stayed")]
        ),
        partnerName: "Oda",
        prefersPartnerAnswersWhenComplete: true
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Complete") {
    DailyPromptCard(
        state: DailyChallengeCardState(
            kind: .complete,
            answeredCount: 2,
            totalCount: 2
        ),
        partnerName: "Oda"
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
