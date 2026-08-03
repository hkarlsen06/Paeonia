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
    /// The single source of truth for what's on screen. The flow moves strictly forward
    /// through these phases and the view switches on this value *alone* — never on the
    /// incidental order in which `isSending` / snapshot signals arrive — so no
    /// answered/"sending" frame can leak out between composing and the reveal.
    @State private var phase: Phase = .composing
    @FocusState private var isComposerFocused: Bool

    /// `.sending` holds the compose screen while the answer syncs and the partner's reply
    /// loads; the screen then turns straight over to `.revealed`. There is intentionally
    /// no separate "answered" phase here — the reveal is the one and only answered surface.
    private enum Phase {
        case composing
        case sending
        case revealed
    }

    var body: some View {
        ZStack {
            switch phase {
            case .composing:
                composing
            case .sending:
                sending
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
            Text(question.prompt)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Keep the answer pinned to the bottom where the live field sat, so nothing
            // jumps as the editable field becomes this read-only one.
            Spacer(minLength: PaeoniaSpacing.space24)

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

    /// The unlocked exchange: the question, both people's status, and both answers with
    /// the partner on top — so answering pays off with their reply right here. Reads
    /// from the live question, so a reply that loads a beat later fills in on its own.
    private var revealed: some View {
        DailyPartnerAnswerRevealView(
            question: question,
            revealedQuestion: revealedQuestion,
            participants: viewModel.participants,
            onDone: dismiss
        )
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

        // Hold on the compose screen (Send still busy) just long enough for the partner's
        // now-unlocked reply to load. Capped, so a slow connection never holds it open.
        phase = .sending
        let didReveal = await viewModel.awaitAnswerReveal(for: question.id)

        if didReveal, revealedQuestion?.canViewPartnerAnswer == true {
            // The reply is viewable — turn the screen straight over to it.
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

/// The revealed exchange shared by the focused partner-answer cover and the main
/// challenge flow. It receives the originally presented question separately from the
/// live snapshot so reloads may reorder the question list without changing the prompt
/// or invalidating the presentation that is already on screen.
struct DailyPartnerAnswerRevealView: View {
    let question: DailyChallengeQuestion
    let revealedQuestion: DailyChallengeQuestion?
    let participants: DailyChallengeParticipants
    let onDone: () -> Void

    var body: some View {
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
                        DailyQuestionStatusView(question: revealedQuestion, participants: participants)
                        DailyAnswerDetailsView(question: revealedQuestion, participants: participants)
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
    }
}
