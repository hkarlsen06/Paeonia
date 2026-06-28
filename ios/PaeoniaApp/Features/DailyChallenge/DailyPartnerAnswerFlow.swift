import SwiftUI

/// The focused, full-screen flow for answering one question your partner has already
/// answered, opened from its card in the Questions tab.
///
/// It reuses the daily challenge's hero morph — the card's CTA glides into the bottom
/// action bar while the prompt and composer wipe open from the centre — but without
/// the multi-question chrome (no eyebrow, step bar, or skip). Sending your answer
/// closes the flow, collapsing back into the card, which now reveals both replies.
struct DailyPartnerAnswerFlow: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var namespace: Namespace.ID?
    /// Namespace for the morphing surface. It stays attached for the flow's whole life
    /// (unlike `namespace`, released the instant a close begins) so the single surface
    /// view can grow open and shrink shut; `isExpanded` picks the direction via
    /// `isSource`.
    var surfaceNamespace: Namespace.ID?
    /// Whether the flow is open. The parent flips it to `false` the moment a close
    /// begins (while still mounted) so the content can collapse in step with the CTA
    /// gliding back to its card.
    var isExpanded = true
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the surface and content are uncovered, 0 (hidden) to 1 (shown). The
    /// gliding button wipes this open as it travels into place, and shut on close.
    @State private var revealProgress: Double = 0
    /// Opacity of the morphing CTA button: solid while it glides, fading only on a
    /// close where the card's CTA is gone (after answering) and it can't glide home.
    @State private var heroOpacity: Double
    /// True from when the answer is queued until the partner's reply has loaded, so the
    /// Send button keeps its busy state while we hold for the reveal before closing.
    @State private var isFinishing = false
    @FocusState private var isComposerFocused: Bool

    init(
        question: DailyChallengeQuestion,
        viewModel: DailyChallengeViewModel,
        namespace: Namespace.ID? = nil,
        surfaceNamespace: Namespace.ID? = nil,
        isExpanded: Bool = true,
        onClose: @escaping () -> Void = {}
    ) {
        self.question = question
        self.viewModel = viewModel
        self.namespace = namespace
        self.surfaceNamespace = surfaceNamespace
        self.isExpanded = isExpanded
        self.onClose = onClose
        _heroOpacity = State(initialValue: isExpanded ? 1 : 0)
    }

    var body: some View {
        ZStack {
            DailyChallengeMorphSurface(
                revealProgress: revealProgress,
                morphID: DailyChallengeMorph.partnerAnswerSurface(question.id),
                namespace: surfaceNamespace,
                isSource: isExpanded
            )

            VStack(spacing: PaeoniaSpacing.space16) {
                DailyChallengeAnswerStep(
                    question: question,
                    viewModel: viewModel,
                    isFocused: $isComposerFocused,
                    revealProgress: revealProgress,
                    revealEnabled: !reduceMotion,
                    morphsPrompt: !reduceMotion,
                    promptMorphID: DailyChallengeMorph.partnerAnswerPrompt(question.id),
                    promptMorphNamespace: namespace,
                    promptOpacity: heroOpacity
                )

                actionBar
            }
            .padding(.top, PaeoniaSpacing.space8)
            // Tap the question or any empty space to put the keyboard away.
            .dismissesKeyboardOnTap { isComposerFocused = false }
        }
        .simultaneousGesture(swipeToDismiss)
        .onAppear { openReveal() }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { openReveal() } else { closeReveal() }
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    private var actionBar: some View {
        DailyChallengeAnswerActionBar(
            primaryTitle: .dailyChallengeSubmitButton,
            isPrimaryBusy: isSubmitting,
            isPrimaryDisabled: isPrimaryDisabled,
            morphNamespace: namespace,
            morphID: DailyChallengeMorph.partnerAnswerButton(question.id),
            chromeOpacity: revealProgress,
            primaryButtonOpacity: heroOpacity,
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

    /// Swipe right from the left edge to leave — the familiar iOS "back" gesture.
    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard
                    value.startLocation.x < 24,
                    value.translation.width > 80,
                    abs(value.translation.width) > abs(value.translation.height)
                else { return }
                PaeoniaHaptics.selection()
                dismiss()
            }
    }

    /// Wipes the surface and content open once on screen, in step with the CTA gliding
    /// in. Under Reduce Motion the parent's plain cross-fade handles the entrance.
    private func openReveal() {
        guard revealProgress < 1 else { return }
        heroOpacity = 1
        if reduceMotion {
            revealProgress = 1
        } else {
            withAnimation(PaeoniaMotion.heroMorph) { revealProgress = 1 }
        }
    }

    /// Wipes the surface and content shut as the CTA glides home. Only under motion;
    /// Reduce Motion cross-fades the whole flow out via the parent instead.
    private func closeReveal() {
        guard !reduceMotion else { return }
        withAnimation(PaeoniaMotion.heroMorph) {
            revealProgress = 0
            heroOpacity = 0
        }
    }

    private func showBanner(for notice: DailyChallengeViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        viewModel.dismissNotice()
    }
}
