import SwiftUI

/// The focused, full-screen flow for answering one question your partner has already
/// answered, opened from its card in the Questions tab (or the history).
///
/// It is presented as a full-screen cover that zooms out of the tapped card, so the
/// card appears to grow into the screen. It reuses the daily challenge's prompt and
/// composer, but without the multi-question chrome (no eyebrow, step bar, or skip).
/// Sending your answer unlocks your partner's reply, which is then revealed right here
/// — the payoff for answering — so the moment doesn't depend on finding the card again
/// in the list afterward. Done closes the flow.
struct DailyPartnerAnswerFlow: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// True from when the answer is queued until the partner's reply has loaded, so the
    /// Send button keeps its busy state while we hold for the reveal.
    @State private var isFinishing = false
    /// Flips to `.revealed` once the answer lands and the partner's reply is viewable,
    /// turning the screen over to the revealed exchange.
    @State private var phase: Phase = .answering
    @FocusState private var isComposerFocused: Bool

    private enum Phase {
        case answering
        case revealed
    }

    var body: some View {
        ZStack {
            switch phase {
            case .answering:
                answering
            case .revealed:
                revealed
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the plum bleed under the keyboard's safe-area region too, so the window's
        // black doesn't show through the keyboard's rounded top corners.
        .background { Color.paeoniaBackgroundPrimary.ignoresSafeArea() }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    // MARK: - Answering

    private var answering: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            DailyChallengeAnswerStep(
                question: question,
                viewModel: viewModel,
                isFocused: $isComposerFocused
            )

            actionBar
        }
        .padding(.top, PaeoniaSpacing.space8)
        .animation(PaeoniaMotion.stateChange, value: isComposerFocused)
        // Tap the question or any empty space to put the keyboard away.
        .dismissesKeyboardOnTap { isComposerFocused = false }
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

    // MARK: - Reveal

    /// The unlocked exchange: the question, both people's status, and both answers with
    /// the partner on top — so answering pays off with their reply right here. Reads
    /// from the live question, so a reply that loads a beat later fills in on its own.
    private var revealed: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                    PaeoniaCardEyebrow(.dailyChallengePartnerRevealEyebrow)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(question.prompt)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let revealedQuestion {
                        DailyQuestionStatusView(question: revealedQuestion, participants: viewModel.participants)
                        DailyAnswerDetailsView(question: revealedQuestion, participants: viewModel.participants)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space24)
                .padding(.bottom, PaeoniaSpacing.space8)
            }

            Button(action: dismiss) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space8)
        }
    }

    // MARK: - State

    /// The live copy of this question from the snapshot, carrying the partner's reply
    /// once it unlocks.
    private var revealedQuestion: DailyChallengeQuestion? {
        viewModel.snapshot.questions.first { $0.id == question.id }
    }

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
        let didAnswer = (revealedQuestion?.hasOwnAnswer ?? false) || viewModel.isSending(question.id)
        guard didAnswer else { return }

        isComposerFocused = false

        // Hold, Send still busy, just long enough for the partner's now-unlocked reply
        // to load. Capped, so a slow connection never holds it open.
        isFinishing = true
        await viewModel.awaitAnswerReveal(for: question.id)
        isFinishing = false

        if revealedQuestion?.canViewPartnerAnswer == true {
            // The reply is viewable — turn the screen over to it.
            PaeoniaHaptics.answerRevealed()
            withAnimation(PaeoniaMotion.meaningfulMoment) { phase = .revealed }
        } else {
            // Offline or still sending: nothing to reveal yet. Close; the card shows
            // both answers once the send syncs and the reply unlocks.
            onClose()
        }
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
