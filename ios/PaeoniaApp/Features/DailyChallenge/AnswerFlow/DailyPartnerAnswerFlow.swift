import SwiftUI

/// The focused, full-screen flow for answering one topic question, opened from its card
/// in the Questions tab or its topic (`TopicAnswerSession`). Daily questions use
/// `DailyChallengeAnswerFlow`.
///
/// It is presented as a full-screen cover that zooms out of the tapped card, so the
/// card appears to grow into the screen. It reuses the daily question's prompt and
/// composer. Sending your answer unlocks your partner's reply when they have answered.
/// Once the answer is saved on this phone, the flow opens the question's chat if the
/// partner has answered. Otherwise the chat would only show the answer just written, so
/// the flow moves on (`onSent`). Close ends the flow at any point.
struct DailyPartnerAnswerFlow: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}
    var onClose: () -> Void = {}
    /// The topic's name, over the question, for a topic question.
    var topicTitle: String?
    /// Puts a topic question aside without asking (`TopicAnswerSession`).
    var onSkip: (() -> Void)?
    /// Moves on to the topic's next question, from the chat's Next.
    var onNext: (() -> Void)?
    /// The answer is saved and the partner has not answered, so there is nothing new to
    /// see. Moves on to the next question with a note that it was sent.
    var onSent: (() -> Void)?
    /// Shows that the previous question's answer was just sent.
    var showsSentNote = false

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// The question's chat, made when the answer is sent.
    @State private var chat: ThreadChatViewModel?
    /// The single source of truth for what's on screen. The flow moves strictly forward
    /// through these phases and the view switches on this value *alone* — never on the
    /// incidental order in which `isSending` / snapshot signals arrive — so no
    /// answered/"sending" frame can leak out between composing and the reveal.
    @State private var phase: Phase = .composing
    /// The question and composer as they were when Send was tapped. Saving the answer
    /// clears the draft and marks the question answered, so the composer shows these
    /// copies until the chat takes over.
    @State private var heldQuestion: DailyChallengeQuestion?
    @State private var visualHold: DailyAnswerStepVisualHold?
    @State private var submittedAnswer: DailySendingPreview?
    @FocusState private var isComposerFocused: Bool

    /// `.sending` holds the composer while the phone prepares the conversation.
    /// The screen then turns straight over to
    /// `.revealed`, the chat. There is intentionally no separate "answered" screen.
    private enum Phase {
        case composing
        case sending
        case revealed
    }

    var body: some View {
        Group {
            if phase == .revealed, let chat {
                DailyAnswerFlowChat(
                    chat: chat,
                    viewModel: viewModel,
                    submittedAnswer: submittedAnswer,
                    privacySafetyService: privacySafetyService,
                    privacyOperationProvider: privacyOperationProvider,
                    onReportedAndLeft: onReportedAndLeft,
                    onClose: dismiss,
                    onNext: onNext
                )
                .transition(.opacity)
            } else {
                answering
            }
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
        .onChange(of: wasAnswerReturned) { _, returned in
            if returned {
                releaseHold()
                withAnimation(PaeoniaMotion.stateChange) { phase = .composing }
            }
        }
    }

    /// The server refused the answer for good and it is back in the composer, so
    /// nothing will unlock. The screen goes back to the question with the answer
    /// still filled in.
    private var wasAnswerReturned: Bool {
        phase == .revealed
            && !viewModel.isSending(question.id)
            && revealedQuestion?.hasOwnAnswer != true
            && viewModel.hasDraftContent(for: question.id)
    }

    /// The question and composer. After Send it stays exactly as it was, with Send
    /// busy, until the chat takes over, so nothing moves in between.
    private var answering: some View {
        VStack(spacing: 0) {
            DailyAnswerFlowHeader(
                question: liveQuestion,
                participants: viewModel.participants,
                onClose: dismiss,
                canSkip: onSkip != nil,
                skipTitle: .dailyChallengeSkipButton,
                isSkipDisabled: isSubmitting,
                onSkip: { onSkip?() },
                sentNote: showsSentNote ? .topicsFlowSentNote(viewModel.participants.partnerName) : nil
            )

            DailyChallengeAnswerStep(
                question: heldQuestion ?? liveQuestion,
                viewModel: viewModel,
                isFocused: $isComposerFocused,
                visualHold: visualHold,
                eyebrow: topicTitle,
                isSubmitting: isSubmitting,
                isSubmitDisabled: isPrimaryDisabled,
                onSubmit: { Task { await submit() } }
            )
            .allowsHitTesting(visualHold == nil)
        }
        .padding(.top, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PaeoniaGlowBackground() }
    }

    // MARK: - State

    /// The live copy of this question from the snapshot, carrying the partner's reply
    /// once it unlocks.
    private var revealedQuestion: DailyChallengeQuestion? {
        viewModel.knownQuestion(question.id)
    }

    /// The live snapshot copy of this question, carrying our just-sent answer once it
    /// lands. Used while composing and for the chat; falls back to the captured
    /// question before the snapshot has it.
    private var liveQuestion: DailyChallengeQuestion {
        revealedQuestion ?? question
    }

    private var isSubmitting: Bool {
        viewModel.submittingQuestionID == question.id || phase == .sending
    }

    private var isPrimaryDisabled: Bool {
        !viewModel.hasDraftToSubmit(for: question) || isSubmitting
    }

    // MARK: - Actions

    private func submit() async {
        guard !isSubmitting else { return }

        let sent = liveQuestion
        heldQuestion = sent
        visualHold = DailyAnswerStepVisualHold(question: sent, viewModel: viewModel)
        await viewModel.submitAnswer(for: question)

        // The answer has landed locally (or staged to send for media). A failure
        // leaves the draft in place and surfaces a banner instead.
        let didAnswer = (revealedQuestion?.hasOwnAnswer ?? false) || viewModel.isSending(question.id)
        guard didAnswer else {
            releaseHold()
            return
        }

        PaeoniaHaptics.answerSent()
        submittedAnswer = viewModel.sendingPreview(for: question)
        isComposerFocused = false

        // Nothing new to see until the partner answers. The composer keeps its hold
        // while the next question fades in, so the sent answer never flashes back.
        if !liveQuestion.hasPartnerAnswer, let onSent {
            onSent()
            return
        }

        // The answer is safe on this phone. Open its conversation without waiting
        // for the upload or the partner's answer.
        phase = .sending
        // Reads the chat from this phone first, so it opens complete. The chat plays
        // the reveal haptic when the partner's answer shows.
        await viewModel.prepareChat(for: liveQuestion)
        let chat = viewModel.makeChatViewModel(question: liveQuestion)
        // Their reply may still be on its way, so it plays the reveal whenever it shows.
        chat.revealsPartnerAnswer = true
        self.chat = chat
        // Slow or offline: the chat still opens, on its waiting page with the answer
        // as saved, and opens up when their reply arrives.
        withAnimation(PaeoniaMotion.meaningfulMoment) { phase = .revealed }
    }

    private func releaseHold() {
        heldQuestion = nil
        visualHold = nil
    }

    private func dismiss() {
        isComposerFocused = false
        onClose()
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
