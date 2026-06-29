import SwiftUI

/// The focused, full-screen flow for answering one question your partner has already
/// answered, opened from its card in the Questions tab.
///
/// It is presented as a full-screen cover that zooms out of the tapped card, so the
/// card appears to grow into the screen. It reuses the daily challenge's prompt and
/// composer, but without the multi-question chrome (no eyebrow, step bar, or skip).
/// Sending your answer closes the flow, shrinking back into the card, which now reveals
/// both replies.
struct DailyPartnerAnswerFlow: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// True from when the answer is queued until the partner's reply has loaded, so the
    /// Send button keeps its busy state while we hold for the reveal before closing.
    @State private var isFinishing = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            DailyChallengeAnswerStep(
                question: question,
                viewModel: viewModel,
                isFocused: $isComposerFocused
            )

            actionBar
        }
        .padding(.top, PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .animation(PaeoniaMotion.stateChange, value: isComposerFocused)
        // Tap the question or any empty space to put the keyboard away.
        .dismissesKeyboardOnTap { isComposerFocused = false }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    private var actionBar: some View {
        DailyChallengeAnswerActionBar(
            primaryTitle: .dailyChallengeSubmitButton,
            isPrimaryBusy: isSubmitting,
            isPrimaryDisabled: isPrimaryDisabled,
            hidesPrimary: isComposerFocused,
            onPrimary: { Task { await submit() } },
            onClose: handleClose
        )
    }

    // MARK: - State

    private var isSubmitting: Bool {
        viewModel.submittingQuestionID == question.id || isFinishing
    }

    private var isPrimaryDisabled: Bool {
        !viewModel.hasDraftToSubmit(for: question) || isSubmitting
    }

    // MARK: - Actions

    private func submit() async {
        guard !isSubmitting else { return }

        await viewModel.submitAnswer(for: question)

        // The answer has landed locally (or staged to send for media). A failure
        // leaves the draft in place and surfaces a banner instead.
        let didAnswer = (viewModel.snapshot.questions
            .first(where: { $0.id == question.id })?.hasOwnAnswer ?? false)
            || viewModel.isSending(question.id)
        guard didAnswer else { return }

        isComposerFocused = false

        // Keep the flow up, Send still busy, just long enough for the partner's
        // now-unlocked reply to load, so collapsing back into the card reveals both
        // answers at once instead of popping the partner's in a beat later. Capped, so
        // a slow connection never holds it open.
        isFinishing = true
        await viewModel.awaitAnswerReveal(for: question.id)
        isFinishing = false

        PaeoniaHaptics.answerRevealed()
        onClose()
    }

    private func dismiss() {
        isComposerFocused = false
        onClose()
    }

    /// While typing, Close puts the keyboard away first and keeps the user on the
    /// question; tapping again (or with the keyboard down) leaves the screen.
    private func handleClose() {
        if isComposerFocused {
            isComposerFocused = false
        } else {
            dismiss()
        }
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
