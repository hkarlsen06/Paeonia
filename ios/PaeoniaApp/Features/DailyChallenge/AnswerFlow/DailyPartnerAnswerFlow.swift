import SwiftUI

/// The focused, full-screen flow for answering one question your partner has already
/// answered, opened from its card in the Questions tab (or the history).
///
/// It is presented as a full-screen cover that zooms out of the tapped card, so the
/// card appears to grow into the screen. It reuses the daily challenge's prompt and
/// composer, but without the multi-question chrome (no eyebrow, step bar, or skip).
/// Sending your answer unlocks your partner's reply. The composer stays as it was
/// until the reply loads, then the flow fades straight into the question's chat, where
/// their answer plays its reveal, so the user can read it and reply without finding
/// the card again. When the send is slow or offline, the chat's waiting page shows the
/// user's answer and opens up once the reply arrives. Close ends the flow at any point.
struct DailyPartnerAnswerFlow: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// The question's chat, made when the answer is sent.
    @State private var chat: DailyQuestionChatViewModel?
    @State private var reportTarget: PrivacyReportTarget?
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
    @FocusState private var isComposerFocused: Bool

    /// `.sending` holds the composer as it was when Send was tapped while the answer
    /// syncs and the partner's reply loads. The screen then turns straight over to
    /// `.revealed`, the chat. There is intentionally no separate "answered" screen.
    private enum Phase {
        case composing
        case sending
        case revealed
    }

    var body: some View {
        Group {
            if phase == .revealed, let chat {
                revealed(chat)
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
        VStack(spacing: PaeoniaSpacing.space16) {
            DailyChallengeAnswerStep(
                question: heldQuestion ?? liveQuestion,
                viewModel: viewModel,
                isFocused: $isComposerFocused,
                visualHold: visualHold
            )
            // The answer is on its way, so the held composer takes no more input.
            .allowsHitTesting(visualHold == nil)

            actionBar
        }
        .padding(.top, PaeoniaSpacing.space8)
        // No explicit animation on this stack: the composer is moved only by the
        // keyboard, via SwiftUI's automatic keyboard-avoidance. Nothing here resizes on
        // focus (the action bar is a constant-height row), so there's no second layout
        // change to animate, and an explicit `.animation` would only re-time the
        // keyboard's movement onto a fixed curve and make it bounce.
        // Tap the question or any empty space to put the keyboard away.
        .dismissesKeyboardOnTap { isComposerFocused = false }
        .paeoniaReadableWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the plum bleed under the keyboard's safe-area region too, so the window's
        // black doesn't show through the keyboard's rounded top corners.
        .background { PaeoniaGlowBackground() }
    }

    private var actionBar: some View {
        DailyChallengeAnswerActionBar(
            primaryTitle: .dailyChallengeSubmitButton,
            isPrimaryBusy: isSubmitting,
            isPrimaryDisabled: isPrimaryDisabled,
            isComposing: isComposerFocused,
            onPrimary: { Task { await submit() } },
            onClose: dismiss,
            onDone: { isComposerFocused = false }
        )
    }

    // MARK: - Reveal

    /// The question's chat: the question, both answers with the partner's lit up, and
    /// the composer. The keyboard stays down so the answer can be read first. Until
    /// the reply unlocks, the chat's waiting page shows the user's answer. After the
    /// couple's day ends, today's snapshot can drop the exchange, so the chat keeps
    /// its own copy of the question instead of going back to the unanswered one.
    private func revealed(_ chat: DailyQuestionChatViewModel) -> some View {
        NavigationStack {
            DailyQuestionChatView(
                viewModel: chat,
                question: revealedQuestion ?? chat.question,
                participants: viewModel.participants,
                onReport: { reportTarget = $0 },
                sendingAnswer: viewModel.sendingPreview(for: liveQuestion),
                onClose: dismiss
            )
            .analyticsScreen("daily_chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(.dailyChallengeFlowClose))
                }
            }
            .navigationDestination(item: $reportTarget) { reportTarget in
                if let partnerUserID = viewModel.participants.partnerUserID {
                    ReportAndLeaveView(
                        partnerUserID: partnerUserID,
                        partnerName: viewModel.participants.partnerName,
                        reportTarget: reportTarget,
                        service: privacySafetyService,
                        operationProvider: privacyOperationProvider,
                        onReportedAndLeft: onReportedAndLeft
                    )
                }
            }
        }
    }

    // MARK: - State

    /// The live copy of this question from the snapshot, carrying the partner's reply
    /// once it unlocks.
    private var revealedQuestion: DailyChallengeQuestion? {
        viewModel.snapshot.questions.first { $0.id == question.id }
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

        isComposerFocused = false

        // Hold the composer as it was (Send still busy) for a moment, so a quick reply
        // turns over in one step. Capped, so a slow connection never holds it here.
        phase = .sending
        _ = await viewModel.awaitAnswerReveal(for: question.id)
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

/// The revealed exchange in the main challenge flow. It receives the originally
/// presented question separately from the live snapshot so reloads may reorder the
/// question list without changing the prompt or invalidating the presentation that is
/// already on screen.
///
/// Until the partner's answer can be shown (the user's answer is still sending, or
/// the reply hasn't loaded), it shows a waiting block for the partner and the user's
/// saved answer. The reply fades in on its own when the live snapshot unlocks it.
struct DailyPartnerAnswerRevealView: View {
    let question: DailyChallengeQuestion
    let revealedQuestion: DailyChallengeQuestion?
    let participants: DailyChallengeParticipants
    /// The user's answer while it's still sending, shown before the server has it.
    var sending: DailySendingPreview?
    /// The partner's answer is on screen, so it counts as seen.
    var onRevealed: (DailyChallengeQuestion) -> Void = { _ in }
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The exchange as last seen unlocked. After the couple's day ends, today's
    /// snapshot can drop a finished exchange, and an open reveal must not lose it.
    @State private var lastRevealed: DailyChallengeQuestion?
    /// The partner's answer starts blurred behind a lock and clears a moment after it
    /// shows. This is the unlock the reveal plays.
    @State private var isPartnerAnswerClear = false

    /// How long the lock shows before the answer clears. Short with Reduce Motion,
    /// which has no lock to look at.
    private var lockHold: Duration {
        .milliseconds(reduceMotion ? 100 : 350)
    }

    private static func isUnlocked(_ question: DailyChallengeQuestion?) -> Bool {
        question?.canViewPartnerAnswer == true && question?.partnerAnswerDetail?.canViewAnswer == true
    }

    /// The live question when it's unlocked, otherwise the last unlocked copy.
    private var shownQuestion: DailyChallengeQuestion? {
        Self.isUnlocked(revealedQuestion) ? revealedQuestion : lastRevealed
    }

    private var isRevealed: Bool {
        shownQuestion != nil
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                    DailyQuestionCard(prompt: question.prompt) {
                        PaeoniaCardEyebrow(.dailyChallengePartnerRevealEyebrow)
                    }

                    if let shownQuestion {
                        revealedContent(shownQuestion)
                    } else {
                        waitingContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space24)
                .padding(.bottom, PaeoniaSpacing.space8)
            }

            Button(action: onDone) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space8)
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: isRevealed)
        .onChange(of: revealedQuestion, initial: true) { _, question in
            if Self.isUnlocked(question) { lastRevealed = question }
        }
        .onChange(of: shownQuestion?.id, initial: true) {
            if let shownQuestion { onRevealed(shownQuestion) }
        }
        .onChange(of: isRevealed) { _, revealed in
            if revealed { PaeoniaHaptics.answerRevealed() }
        }
        .task(id: shownQuestion?.id) {
            guard shownQuestion != nil else { return }
            try? await Task.sleep(for: lockHold)
            guard !Task.isCancelled else { return }
            withAnimation(PaeoniaMotion.standardCurve(duration: reduceMotion ? PaeoniaMotion.motionDefault : 0.7)) {
                isPartnerAnswerClear = true
            }
        }
    }

    /// The partner's answer, unlocking from blurred to clear, then a line about how
    /// the two picks lined up when this is a "who is more likely" question.
    @ViewBuilder
    private func revealedContent(_ shownQuestion: DailyChallengeQuestion) -> some View {
        DailyQuestionStatusView(question: shownQuestion, participants: participants)
        DailyAnswerDetailsView(
            question: shownQuestion,
            participants: participants,
            partnerAnswerIsClear: isPartnerAnswerClear
        )
        .transition(.opacity)

        if isPartnerAnswerClear,
           let match = shownQuestion.partnerChoiceMatch(participants: participants) {
            PartnerChoiceMatchBanner(
                match: match,
                partnerName: participants.partnerName,
                celebrates: true
            )
            .transition(.opacity)
        }
    }

    /// The partner's reply is on its way: a calm waiting block for them, then the
    /// user's own answer as it was saved.
    @ViewBuilder
    private var waitingContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(verbatim: participants.partnerName)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            HStack(spacing: PaeoniaSpacing.space12) {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                Text(.dailyChallengePartnerRevealWaiting(participants.partnerName))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .accessibilityElement(children: .combine)

        if let sending {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(.dailyChallengeChoiceYou)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)

                DailySendingAnswerView(
                    mediaKind: sending.mediaKind,
                    mediaData: sending.mediaData,
                    voiceDurationMs: sending.voiceDurationMs,
                    partnerChoiceName: sending.partnerChoiceName,
                    text: sending.text,
                    showsSendingStatus: sending.isHeldOnPhone
                )
            }
            .padding(PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        } else if let revealedQuestion, revealedQuestion.ownAnswerDetail != nil {
            DailyAnswerDetailsView(question: revealedQuestion, participants: participants)
        }
    }
}
