import SwiftUI

/// The focused, full-screen flow for answering one question your partner has already
/// answered, opened from its card in the Questions tab (or the history).
///
/// It is presented as a full-screen cover that zooms out of the tapped card, so the
/// card appears to grow into the screen. It reuses the daily challenge's prompt and
/// composer, but without the multi-question chrome (no eyebrow, step bar, or skip).
/// Sending your answer unlocks your partner's reply, and the flow turns into the
/// question's chat with their answer lit up, so the user can read it and reply
/// without finding the card again. When the send is slow or offline, the chat's
/// waiting page shows the user's answer and opens up once the reply arrives. Close
/// ends the flow at any point.
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
    @FocusState private var isComposerFocused: Bool

    /// `.sending` holds the compose screen while the answer syncs and the partner's reply
    /// loads; the screen then turns straight over to `.revealed`, the chat. There is
    /// intentionally no separate "answered" phase here.
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

    private var answering: some View {
        ZStack {
            if phase == .composing {
                composing
            } else {
                sending
            }
        }
        .paeoniaReadableWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the plum bleed under the keyboard's safe-area region too, so the window's
        // black doesn't show through the keyboard's rounded top corners.
        .background { PaeoniaGlowBackground() }
    }

    // MARK: - Composing

    private var composing: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            DailyChallengeAnswerStep(
                question: liveQuestion,
                viewModel: viewModel,
                isFocused: $isComposerFocused
            )

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
    }

    // MARK: - Sending (holding for the reveal)

    /// The held screen between Send and the reveal. It is its own phase — not the compose
    /// step with a flag — so nothing it shows depends on live `isSending`/snapshot flags,
    /// and it is the view that stays on screen (and fades out) as the reveal turns over.
    private var sending: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            committedAnswer
            actionBar
        }
        .padding(.top, PaeoniaSpacing.space8)
    }

    /// Keeps the *compose* look — the question up top and our just-sent answer read-only
    /// in the same field below — so the screen holds steady until the reveal cross-fades
    /// in. It never shows an answered/"saving" state; the reveal is the only answered
    /// surface.
    private var committedAnswer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            // The same card the composer showed, with the same waiting hint, so
            // nothing jumps as the editable field becomes this read-only one.
            DailyQuestionCard(prompt: question.prompt) {
                DailyAnswerKindBadges(kinds: question.composableAnswerKinds)
            } footer: {
                if question.partnerAnswer != nil, !question.canViewPartnerAnswer {
                    DailyPartnerWaitingNote(partnerName: viewModel.participants.partnerName)
                }
            }
            .frame(maxHeight: .infinity)

            committedAnswerField
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space24)
        .padding(.bottom, PaeoniaSpacing.space8)
    }

    /// The just-sent answer shown read-only in the same labelled, bordered field the
    /// composer used, so it reads as "your answer, still on screen" rather than a reveal.
    /// Sources the content from the in-flight send, falling back to the live snapshot so
    /// it stays filled across the moment the send settles and the reveal takes over.
    private var committedAnswerField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.dailyChallengeTextAnswerLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            DailySendingAnswerView(
                mediaKind: liveQuestion.mediaAnswerKind,
                mediaData: viewModel.sendingMediaData(for: question.id),
                voiceDurationMs: viewModel.sendingVoiceDurationMs(for: question.id),
                partnerChoiceName: viewModel.sendingPartnerChoiceName(for: question.id),
                text: viewModel.sendingText(for: question.id) ?? liveQuestion.ownAnswerDetail?.textBody,
                showsSendingStatus: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PaeoniaSpacing.space12)
            .background(.paeoniaBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
        }
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
                revealsPartnerAnswer: true,
                onClose: dismiss
            )
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
    /// lands. Used while composing and to source the held answer; falls back to the
    /// captured question before the snapshot has it.
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

        await viewModel.submitAnswer(for: question)

        // The answer has landed locally (or staged to send for media). A failure
        // leaves the draft in place and surfaces a banner instead.
        let didAnswer = (revealedQuestion?.hasOwnAnswer ?? false) || viewModel.isSending(question.id)
        guard didAnswer else { return }

        isComposerFocused = false

        // Hold on the compose screen (Send still busy) for a moment, so a quick reply
        // turns over in one step. Capped, so a slow connection never holds it here.
        phase = .sending
        _ = await viewModel.awaitAnswerReveal(for: question.id)
        // Reads the chat from this phone first, so it opens complete. The chat plays
        // the reveal haptic when the partner's answer shows.
        await viewModel.prepareChat(for: liveQuestion)
        chat = viewModel.makeChatViewModel(question: liveQuestion)
        // Slow or offline: the chat still opens, on its waiting page with the answer
        // as saved, and opens up when their reply arrives.
        withAnimation(PaeoniaMotion.meaningfulMoment) { phase = .revealed }
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
                        DailyQuestionStatusView(question: shownQuestion, participants: participants)
                        DailyAnswerDetailsView(question: shownQuestion, participants: participants)
                            .transition(.opacity)
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
                    text: sending.text
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
