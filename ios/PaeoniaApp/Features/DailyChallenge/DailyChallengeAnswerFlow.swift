import SwiftUI

/// Identifiers for the elements that morph (PowerPoint-style) between the compact
/// prompt card and the full answering flow. The card tags these elements while it
/// is the active, collapsed entry point; the flow tags the same ids once expanded,
/// so SwiftUI glides each one from its card position into its flow position.
enum DailyChallengeMorph {
    static let eyebrow = "dailyChallenge.morph.eyebrow"
    static let stepBar = "dailyChallenge.morph.stepBar"
    static let primaryButton = "dailyChallenge.morph.primaryButton"
}

extension View {
    /// Applies `matchedGeometryEffect` only when a namespace is provided. A nil
    /// namespace means "don't take part in the morph" — used so the card stops
    /// owning the shared ids while the flow is expanded (and vice versa), which is
    /// what lets the elements travel instead of staying pinned to one side.
    @ViewBuilder
    func dailyChallengeMorph(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace, properties: .frame, anchor: .center)
        } else {
            self
        }
    }
}

private extension View {
    /// Dismisses the keyboard when the user taps anywhere on the view that isn't an
    /// interactive control. This is a convenience for sighted users, not an
    /// accessibility control, so it intentionally does not advertise a button trait
    /// (VoiceOver dismisses the keyboard through its own affordances).
    func dismissesKeyboardOnTap(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

/// The focused, full-screen answering experience for today's daily challenge.
///
/// It expands out of the Us-tab prompt card (and the Questions overview) with a
/// hero morph: the eyebrow, the three-step bar, and the primary button travel from
/// their card positions into this screen, while the question body and composer
/// cross-fade in. The body steps through one question at a time, a quiet "Skip"
/// swaps an unanswered question for a fresh one (the backend caps swaps per day),
/// and a left-edge swipe-right — or the Close button — shrinks it back.
struct DailyChallengeAnswerFlow: View {
    let viewModel: DailyChallengeViewModel
    var namespace: Namespace.ID?
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var index = 0
    @State private var didSetInitialIndex = false
    @State private var didCelebrate = false
    @FocusState private var isComposerFocused: Bool

    private enum Phase {
        case loading
        case answering
        case unavailable
        case complete
    }

    private var questions: [DailyChallengeQuestion] {
        viewModel.snapshot.answerFlowQuestions
    }

    private var phase: Phase {
        if didCelebrate { return .complete }
        if !questions.isEmpty { return .answering }
        if viewModel.isStarting || viewModel.isLoading { return .loading }
        return .unavailable
    }

    var body: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary.ignoresSafeArea()

            switch phase {
            case .complete:
                DailyChallengeCompletionView(onDone: dismiss)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            case .loading:
                loadingState
            case .unavailable:
                unavailableState
            case .answering:
                answeringState
            }
        }
        .simultaneousGesture(swipeToDismiss)
        .animation(PaeoniaMotion.cardReveal, value: didCelebrate)
        .onAppear { setInitialIndexIfNeeded() }
        .onChange(of: questions.count) { _, newCount in
            setInitialIndexIfNeeded()
            // Keep the selected step valid if the list shrinks under us.
            if newCount > 0, index > newCount - 1 {
                index = newCount - 1
            }
        }
        .onChange(of: index) { _, _ in isComposerFocused = false }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    // MARK: - States

    /// Eyebrow + step bar. Both carry the morph ids so they fly in from the card,
    /// and they render the same way in every phase so those morph targets always
    /// exist while the screen opens. The step bar is a progress meter only — moving
    /// between questions is deliberate, via the button. Close lives in the bottom
    /// action bar, within thumb reach.
    private var header: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            PaeoniaCardEyebrow(.dailyChallengeFlowEyebrow)
                .dailyChallengeMorph(DailyChallengeMorph.eyebrow, in: namespace)
                .frame(maxWidth: .infinity, alignment: .leading)

            DailyChallengeStepBar(
                total: max(questions.count, DailyChallengeProgress.requiredOwnQuestionCount),
                completed: answeredCount,
                current: questions.isEmpty ? nil : boundedIndex,
                height: 8,
                onSelect: questions.isEmpty ? nil : { (step: Int) in goToStep(step) }
            )
            .dailyChallengeMorph(DailyChallengeMorph.stepBar, in: namespace)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
    }

    private var answeringState: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            header

            if let question = currentQuestion {
                DailyChallengeAnswerStep(
                    question: question,
                    viewModel: viewModel,
                    isFocused: $isComposerFocused
                )
                .id(question.id)
                // Neutral fade: the user can move forward (Send) or jump to any
                // step in the bar, so a directional slide would read wrong one way.
                .transition(.opacity)
            }

            actionBar
        }
        // Tap the question or any empty space to put the keyboard away. The field
        // and buttons keep their own taps; this only catches what they don't.
        .dismissesKeyboardOnTap { isComposerFocused = false }
    }

    private var actionBar: some View {
        DailyChallengeAnswerActionBar(
            primaryTitle: primaryActionTitle,
            isPrimaryBusy: isSubmittingCurrent,
            isPrimaryDisabled: isPrimaryDisabled,
            canSkip: canSkipCurrent,
            isSkipBusy: isShufflingCurrent,
            isSkipDisabled: isShufflingCurrent || hasDraftForCurrent,
            morphNamespace: namespace,
            onPrimary: handlePrimary,
            onClose: handleClose,
            onSkip: { Task { await skipCurrent() } }
        )
    }

    private var loadingState: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            header
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.paeoniaAccentPrimary)
            Spacer()
        }
    }

    private var unavailableState: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            header
            Spacer()
            PaeoniaEmptyStateView(
                title: .dailyChallengeHomeNoChallengeTitle,
                message: .dailyChallengeHomeNoChallengeMessage,
                systemImage: "sparkles"
            )
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            Spacer()
            Button(action: onClose) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
    }

    // MARK: - Current question helpers

    private var boundedIndex: Int {
        guard !questions.isEmpty else { return 0 }
        return min(max(index, 0), questions.count - 1)
    }

    private var currentQuestion: DailyChallengeQuestion? {
        guard !questions.isEmpty else { return nil }
        return questions[boundedIndex]
    }

    private var isLastStep: Bool {
        boundedIndex >= questions.count - 1
    }

    private var answeredCount: Int {
        // A staged photo that's still uploading counts toward progress — it's done
        // from the user's side.
        questions.filter { $0.hasOwnAnswer || viewModel.isSending($0.id) }.count
    }

    private var answerableIndices: [Int] {
        questions.indices.filter {
            !questions[$0].hasOwnAnswer
                && questions[$0].isAvailableToAnswer
                && !viewModel.isSending(questions[$0].id)
        }
    }

    private var isSubmittingCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.submittingQuestionID == currentQuestion.id
    }

    private var isShufflingCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.isShuffling(currentQuestion)
    }

    private var canSkipCurrent: Bool {
        guard let currentQuestion else { return false }
        return currentQuestion.origin == .own
            && !currentQuestion.hasOwnAnswer
            && currentQuestion.isAvailableToAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True once the draft holds a real answer. Skipping discards it, so Skip must
    /// not be reachable while there's an answer in progress.
    private var hasDraftForCurrent: Bool {
        guard let currentQuestion else { return false }
        return viewModel.hasDraftToSubmit(for: currentQuestion)
    }

    /// The flow's primary button sends a new answer when one is being typed, saves
    /// an edit to an answer that can still be changed, or just moves the user along.
    private var isPrimaryActionSend: Bool {
        guard let currentQuestion else { return false }
        return !currentQuestion.hasOwnAnswer
            && currentQuestion.canSubmitAnswer
            && !viewModel.isSending(currentQuestion.id)
    }

    /// True only when the user has actually changed a previously sent answer (and
    /// not blanked it). When there's no change, the button becomes Next/Done instead
    /// so they can step forward without reaching for the progress bar.
    private var isPrimaryActionSave: Bool {
        guard let currentQuestion, let kind = currentQuestion.editableAnswerKind else { return false }
        switch kind {
        case .partnerChoice:
            guard let draft = viewModel.partnerChoiceSelection(for: currentQuestion.id) else { return false }
            return draft != currentQuestion.ownAnswerDetail?.selectedUserID
        default:
            let draft = viewModel.draftText(for: currentQuestion.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = (currentQuestion.ownAnswerDetail?.textBody ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !draft.isEmpty && draft != saved
        }
    }

    private var primaryActionTitle: LocalizedStringResource {
        if isPrimaryActionSend { return .dailyChallengeSubmitButton }
        if isPrimaryActionSave { return .dailyChallengeFlowSaveButton }
        return isLastStep ? .dailyChallengeFlowDoneButton : .dailyChallengeFlowNextButton
    }

    private var isPrimaryDisabled: Bool {
        guard let currentQuestion else { return false }

        if isPrimaryActionSend {
            return !viewModel.hasDraftToSubmit(for: currentQuestion) || isSubmittingCurrent || isShufflingCurrent
        }

        if isPrimaryActionSave {
            return isSubmittingCurrent
        }

        // Next / Done is plain navigation, always available.
        return false
    }

    // MARK: - Actions

    private func handlePrimary() {
        if isPrimaryActionSend {
            Task { await submitCurrent() }
        } else if isPrimaryActionSave {
            Task { await editCurrent() }
        } else {
            advanceOrFinish()
        }
    }

    /// Move to the next question, or leave the flow when this is the last one.
    private func advanceOrFinish() {
        if isLastStep {
            dismiss()
        } else {
            withAnimation(PaeoniaMotion.stateChange) { index = boundedIndex + 1 }
        }
    }

    private func dismiss() {
        isComposerFocused = false
        onClose()
    }

    /// While the user is typing, Close puts the keyboard away first and keeps them
    /// on the question; tapping it again (or when the keyboard is already down)
    /// leaves the screen. This guards against an accidental exit mid-answer.
    private func handleClose() {
        if isComposerFocused {
            isComposerFocused = false
        } else {
            dismiss()
        }
    }

    /// Swipe right from the left edge to leave — the familiar iOS "back" gesture.
    /// It's a pure trigger: the screen doesn't follow the finger. A qualifying swipe
    /// gives a light haptic and closes exactly like the Close button (morphing back
    /// into the card). Starting at the edge keeps it clear of text selection.
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

    private func submitCurrent() async {
        guard let question = currentQuestion else { return }

        await viewModel.submitAnswer(for: question)

        // Advance once the answer has landed on the server or — for a photo — been
        // staged to send in the background. A failure leaves the draft in place and
        // surfaces a banner instead.
        let didAnswer = (viewModel.snapshot.answerFlowQuestions
            .first(where: { $0.id == question.id })?.hasOwnAnswer ?? false)
            || viewModel.isSending(question.id)
        guard didAnswer else { return }

        isComposerFocused = false

        if answerableIndices.isEmpty {
            celebrate()
        } else if let next = nextAnswerableIndex(after: boundedIndex) {
            withAnimation(PaeoniaMotion.stateChange) { index = next }
        }
    }

    private func editCurrent() async {
        guard let question = currentQuestion, let kind = question.editableAnswerKind else { return }

        switch kind {
        case .partnerChoice:
            let attempted = viewModel.partnerChoiceSelection(for: question.id)
            await viewModel.editPartnerChoiceAnswer(for: question)

            // Move on only if the save landed; a failure keeps the user here with a banner.
            let savedNow = viewModel.snapshot.answerFlowQuestions
                .first(where: { $0.id == question.id })?
                .ownAnswerDetail?.selectedUserID
            if savedNow == attempted {
                advanceOrFinish()
            }
        default:
            let attempted = viewModel.draftText(for: question.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await viewModel.editTextAnswer(for: question)
            isComposerFocused = false

            let savedNow = viewModel.snapshot.answerFlowQuestions
                .first(where: { $0.id == question.id })?
                .ownAnswerDetail?.textBody?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if savedNow == attempted {
                advanceOrFinish()
            }
        }
    }

    private func skipCurrent() async {
        guard let question = currentQuestion else { return }
        isComposerFocused = false
        await viewModel.shuffle(question)
    }

    /// Jump to a question tapped in the progress bar. Drafts are kept, so an
    /// unanswered question reopens with your in-progress text; an answered one opens
    /// to review what you sent.
    private func goToStep(_ step: Int) {
        guard step >= 0, step < questions.count, step != boundedIndex else { return }
        isComposerFocused = false
        withAnimation(PaeoniaMotion.stateChange) { index = step }
    }

    private func nextAnswerableIndex(after current: Int) -> Int? {
        answerableIndices.first(where: { $0 > current }) ?? answerableIndices.first
    }

    private func setInitialIndexIfNeeded() {
        guard !didSetInitialIndex, !questions.isEmpty else { return }
        didSetInitialIndex = true
        if let first = nextAnswerableIndex(after: -1) {
            index = first
        }
    }

    private func celebrate() {
        isComposerFocused = false
        PaeoniaHaptics.answerRevealed()
        withAnimation(PaeoniaMotion.cardReveal) { didCelebrate = true }
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

// MARK: - One question

private struct DailyChallengeAnswerStep: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        // Text answers sit low so the field lands right under the question and just
        // above the keyboard (the action bar keeps keyboard avoidance). Tap-only
        // composers — partner choice, photo, voice — and review states read better
        // anchored under the question near the top, with the choice below it.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Text(question.prompt)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            answerSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pinsToBottom ? .bottom : .top)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, pinsToBottom ? 0 : PaeoniaSpacing.space24)
        .padding(.bottom, PaeoniaSpacing.space8)
        .onAppear(perform: seedEditDraftIfNeeded)
    }

    /// Whether the active composer is a keyboard text field, which should hug the
    /// bottom. Everything else (choice avatars, media, review) anchors to the top.
    private var pinsToBottom: Bool {
        if viewModel.isSending(question.id) { return false }
        if let editKind = question.editableAnswerKind { return editKind == .text }
        if question.hasOwnAnswer { return false }
        if question.canSubmitAnswer { return viewModel.composeKind(for: question) == .text }
        return false
    }

    @ViewBuilder
    private var answerSection: some View {
        if viewModel.isSending(question.id) {
            DailySendingAnswerView(imageData: viewModel.sendingMediaData(for: question.id))
        } else if let editKind = question.editableAnswerKind {
            editComposer(kind: editKind)
        } else if question.hasOwnAnswer {
            DailyQuestionStatusView(question: question)
            DailyAnswerDetailsView(question: question, participants: viewModel.participants)
        } else if question.canSubmitAnswer {
            if question.partnerAnswer != nil, !question.canViewPartnerAnswer {
                DailyPartnerWaitingNote()
            }
            composer
        } else {
            DailyUnsupportedAnswerMessage(answerKinds: question.answerKinds)
        }
    }

    /// The composer for an answer the user already sent but can still change while
    /// it's private. Text reopens the editable field; partner choice reopens the
    /// avatar picker (pre-selected) with a line showing when it was answered.
    @ViewBuilder
    private func editComposer(kind: DailyChallengeAnswerKind) -> some View {
        switch kind {
        case .partnerChoice:
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                DailyQuestionStatusView(question: question)

                if let options = viewModel.participants.partnerChoiceOptions {
                    DailyPartnerChoicePicker(
                        options: options,
                        selection: viewModel.partnerChoiceSelection(for: question.id),
                        onSelect: { viewModel.setPartnerChoice($0, for: question.id) }
                    )
                } else {
                    DailyAnswerDetailsView(question: question, participants: viewModel.participants)
                }
            }
        default:
            DailyAnswerTextField(text: draftBinding, isFocused: isFocused)
        }
    }

    /// Shows the input for the question's composable kind. When a question accepts
    /// more than one kind (e.g. photo or text), a small picker lets the user choose
    /// which to answer with first.
    @ViewBuilder
    private var composer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            if question.composableAnswerKinds.count > 1 {
                DailyAnswerKindPicker(
                    kinds: question.composableAnswerKinds,
                    selection: viewModel.composeKind(for: question),
                    onSelect: { viewModel.setComposeKind($0, for: question.id) }
                )
            }

            kindComposer
        }
    }

    @ViewBuilder
    private var kindComposer: some View {
        switch viewModel.composeKind(for: question) {
        case .partnerChoice:
            if let options = viewModel.participants.partnerChoiceOptions {
                DailyPartnerChoicePicker(
                    options: options,
                    selection: viewModel.partnerChoiceSelection(for: question.id),
                    onSelect: { viewModel.setPartnerChoice($0, for: question.id) }
                )
            } else {
                DailyUnsupportedAnswerMessage(answerKinds: question.answerKinds)
            }
        case .photo:
            DailyPhotoAnswerComposer(
                imageData: viewModel.stagedMediaData(for: question.id),
                onPick: { viewModel.stagePhoto($0, for: question.id) },
                onRemove: { viewModel.removeStagedMedia(for: question.id) }
            )
        case .voice:
            voiceComposer
        default:
            DailyAnswerTextField(text: draftBinding, isFocused: isFocused)
        }
    }

    @ViewBuilder
    private var voiceComposer: some View {
        if let voiceData = viewModel.stagedMediaData(for: question.id) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(.dailyChallengeVoiceLabel)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)

                DailyVoicePlaybackView(
                    source: .data(voiceData),
                    fallbackDurationMs: viewModel.stagedVoiceDurationMs(for: question.id)
                )

                Button {
                    viewModel.removeStagedMedia(for: question.id)
                } label: {
                    Label {
                        Text(.dailyChallengeVoiceReRecord)
                    } icon: {
                        Image(systemName: "arrow.counterclockwise").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity)
            }
        } else {
            DailyVoiceRecorderView(
                onRecorded: { url, durationMs in
                    viewModel.stageVoice(url: url, durationMs: durationMs, for: question.id)
                }
            )
        }
    }

    /// When revisiting an answer you can still edit, start the composer from what you
    /// previously sent (unless you already have an unsaved edit in progress).
    private func seedEditDraftIfNeeded() {
        switch question.editableAnswerKind {
        case .text:
            guard
                viewModel.draftText(for: question.id).isEmpty,
                let existing = question.ownAnswerDetail?.textBody,
                !existing.isEmpty
            else { return }
            viewModel.setDraftText(existing, for: question.id)
        case .partnerChoice:
            guard
                viewModel.partnerChoiceSelection(for: question.id) == nil,
                let existing = question.ownAnswerDetail?.selectedUserID
            else { return }
            viewModel.setPartnerChoice(existing, for: question.id)
        default:
            break
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { viewModel.draftText(for: question.id) },
            set: { viewModel.setDraftText($0, for: question.id) }
        )
    }
}

private struct DailyPartnerWaitingNote: View {
    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "lock.circle.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            Text(.dailyChallengePartnerHiddenMessage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
    }
}

// MARK: - Bottom action bar

private struct DailyChallengeAnswerActionBar: View {
    let primaryTitle: LocalizedStringResource
    let isPrimaryBusy: Bool
    let isPrimaryDisabled: Bool
    let canSkip: Bool
    let isSkipBusy: Bool
    let isSkipDisabled: Bool
    var morphNamespace: Namespace.ID?
    let onPrimary: () -> Void
    let onClose: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            primaryButton
            secondaryRow
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.space8)
        .background(.paeoniaBackgroundPrimary)
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            if isPrimaryBusy {
                ProgressView().tint(.paeoniaTextInverse)
            } else {
                Text(primaryTitle)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(isPrimaryDisabled || isPrimaryBusy)
        .dailyChallengeMorph(DailyChallengeMorph.primaryButton, in: morphNamespace)
    }

    // Close sits on the left, Skip on the right, with a thin divider between them.
    private var secondaryRow: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Label {
                    Text(.dailyChallengeFlowClose)
                } icon: {
                    Image(systemName: "xmark").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)

            if canSkip {
                Rectangle()
                    .fill(.paeoniaSurfacePressed)
                    .frame(width: PaeoniaRadius.strokeDefault, height: PaeoniaSpacing.space24)

                Button(action: onSkip) {
                    if isSkipBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label {
                            Text(.dailyChallengeSkipButton)
                        } icon: {
                            Image(systemName: "shuffle").accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .disabled(isSkipDisabled)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: PaeoniaSpacing.compactButtonHeight)
    }
}

// MARK: - Completion

private struct DailyChallengeCompletionView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.dailyChallengeFlowAllDoneTitle)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.dailyChallengeFlowAllDoneMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            Spacer()

            Button(action: onDone) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    DailyChallengeAnswerFlowPreviewHost()
}

private struct DailyChallengeAnswerFlowPreviewHost: View {
    @State private var viewModel = DailyChallengeViewModel(service: PreviewDailyChallengeService())

    var body: some View {
        DailyChallengeAnswerFlow(viewModel: viewModel)
            .environment(PaeoniaBannerCenter())
            .preferredColorScheme(.dark)
            .task {
                await viewModel.configure(currentUserID: PreviewDailyChallengeService.userID)
            }
    }
}
#endif
