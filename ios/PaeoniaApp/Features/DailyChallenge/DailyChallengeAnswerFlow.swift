import SwiftUI

/// Stable source ids for the Daily Challenge zoom transition. The Home prompt card and
/// the Questions-tab hero card each tag themselves with one of these via
/// `.matchedTransitionSource`, and `MainTabView` zooms the answer flow's full-screen
/// cover out of whichever card opened it. (Partner-answer cards use their question id.)
enum DailyFlowZoom {
    static let home = "dailyFlow.home"
    static let questions = "dailyFlow.questions"
}

extension View {
    /// Marks this view as the source the answer flow zooms out of, but only when a
    /// namespace is provided. A nil namespace passes through untouched — used by
    /// previews (which present no flow) and to skip the source under Reduce Motion.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Zooms a presentation out of its matching `zoomSource(_:in:)`, so the source card
    /// appears to grow into the full-screen cover. When `enabled` is false (Reduce
    /// Motion) or no namespace is provided, the cover keeps its default transition.
    @ViewBuilder
    func zoomTransition(_ id: some Hashable, in namespace: Namespace.ID?, enabled: Bool) -> some View {
        if enabled, let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// Dismisses the keyboard when the user taps anywhere on the view that isn't an
    /// interactive control. This is a convenience for sighted users, not an
    /// accessibility control, so it intentionally does not advertise a button trait
    /// (VoiceOver dismisses the keyboard through its own affordances). Shared by the
    /// daily challenge flow and the Questions-tab partner-answer flow.
    func dismissesKeyboardOnTap(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

/// The focused, full-screen answering experience for today's daily challenge.
///
/// It is presented as a full-screen cover that zooms out of the card that opened it
/// (the Us-tab prompt card or the Questions overview hero card), so the card appears to
/// grow into the screen. The body steps through one question at a time, a quiet "Skip"
/// swaps an unanswered question for a fresh one (the backend caps swaps per day), and
/// the Close button — or a drag-down — shrinks it back into the card.
struct DailyChallengeAnswerFlow: View {
    let viewModel: DailyChallengeViewModel
    var onClose: () -> Void = {}
    /// Opens the streak-restore offer from the completion screen when a lost
    /// streak can still be bought back.
    var onRestore: () -> Void = {}
    /// Opens the Questions tab so the user can pick up optional partner
    /// answers after their required streak questions are finished.
    var onOpenPartnerQuestions: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var requiredQuestions: [DailyChallengeQuestion] {
        viewModel.snapshot.ownQuestions
    }

    private var hasPartnerQuestionsToAnswer: Bool {
        viewModel.snapshot.hasAnswerablePartnerQuestions
    }

    private var phase: Phase {
        if didCelebrate { return .complete }
        if !questions.isEmpty { return .answering }
        if viewModel.isStarting || viewModel.isLoading { return .loading }
        return .unavailable
    }

    /// The streak shown on the completion celebration.
    ///
    /// Answers send local-first, so the stored streak may not yet reflect today
    /// when this screen appears. We predict today's increment from the stored
    /// streak and the couple's local date — the same rule the server applies once
    /// the answer lands — so the number is right immediately and offline.
    private var currentStreak: Int {
        StreakCelebration.celebratedCount(
            serverCurrentCount: viewModel.streak.currentCount,
            lastQualifiedDate: viewModel.streak.lastQualifiedDate,
            todayLocalDate: viewModel.snapshot.questions.first?.localDate
        )
    }

    /// Drives the answering → completion swap. A gentle celebratory bloom under
    /// motion; a plain timed cross-fade when Reduce Motion is on.
    private var celebrateAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: PaeoniaMotion.motionDefault)
            : PaeoniaMotion.celebrationReveal
    }

    /// The completion surface grows in from slightly smaller as the question fades
    /// out, so the streak screen reads as a reward arriving rather than a swap.
    /// Reduce Motion drops the scale and keeps only the cross-fade.
    private var completionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.92))
    }

    var body: some View {
        ZStack {
            switch phase {
            case .complete:
                DailyChallengeCompletionView(
                    streak: currentStreak,
                    partnerName: viewModel.participants.partnerName,
                    restorableCount: viewModel.streak.isRestorable ? viewModel.streak.restorableCount : nil,
                    onRestore: onRestore,
                    hasPartnerQuestionsToAnswer: hasPartnerQuestionsToAnswer,
                    onOpenPartnerQuestions: onOpenPartnerQuestions,
                    onDone: dismiss
                )
                .transition(completionTransition)
            case .loading:
                loadingState
            case .unavailable:
                unavailableState
            case .answering:
                answeringState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the plum bleed under the keyboard's safe-area region too. Keyboard
        // avoidance otherwise shrinks this surface above the keyboard, so the window's
        // black showed through the keyboard's rounded top corners.
        .background { Color.paeoniaBackgroundPrimary.ignoresSafeArea() }
        .animation(celebrateAnimation, value: didCelebrate)
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

    /// Eyebrow + step bar. The step bar is a progress meter only — moving between
    /// questions is deliberate, via the button. Close lives in the bottom action bar,
    /// within thumb reach.
    private var header: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            PaeoniaCardEyebrow(.dailyChallengeFlowEyebrow)
                .frame(maxWidth: .infinity, alignment: .leading)

            DailyChallengeStepBar(
                total: DailyChallengeProgress.requiredOwnQuestionCount,
                completed: answeredRequiredCount,
                current: currentRequiredStep,
                height: 8,
                onSelect: requiredQuestions.isEmpty ? nil : { (step: Int) in goToRequiredStep(step) }
            )
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
    }

    private var answeringState: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            // The header stays put while the keyboard is up. It anchors the top of the
            // screen, so the question doesn't jump when the field focuses — room for the
            // composer comes from the Send button folding away below and (for photo
            // questions) the picked photo folding away, not from moving the top.
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
        .animation(PaeoniaMotion.stateChange, value: isComposerFocused)
        // Tap the question or any empty space to put the keyboard away. The field
        // and buttons keep their own taps; this only catches what they don't.
        .dismissesKeyboardOnTap { isComposerFocused = false }
    }

    private var actionBar: some View {
        DailyChallengeAnswerActionBar(
            primaryTitle: primaryActionTitle,
            isPrimaryBusy: isSubmittingCurrent,
            isPrimaryDisabled: isPrimaryDisabled,
            hidesPrimary: isComposerFocused,
            canSkip: canSkipCurrent,
            isSkipBusy: isShufflingCurrent,
            isSkipDisabled: isShufflingCurrent || hasDraftForCurrent,
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

    private var currentRequiredStep: Int? {
        guard let currentQuestion, currentQuestion.origin == .own else { return nil }
        return requiredQuestions.firstIndex { $0.id == currentQuestion.id }
    }

    private var answeredRequiredCount: Int {
        // A staged photo that's still uploading counts toward progress — it's done
        // from the user's side.
        min(
            requiredQuestions.filter { $0.hasOwnAnswer || viewModel.isSending($0.id) }.count,
            DailyChallengeProgress.requiredOwnQuestionCount
        )
    }

    private var hasFinishedRequiredQuestions: Bool {
        answeredRequiredCount >= DailyChallengeProgress.requiredOwnQuestionCount
    }

    private var answerableIndices: [Int] {
        questions.indices.filter {
            !questions[$0].hasOwnAnswer
            && questions[$0].isAvailableToAnswer
            && !viewModel.isSending(questions[$0].id)
        }
    }

    private var answerableRequiredIndices: [Int] {
        answerableIndices.filter { questions[$0].origin == .own }
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

        if question.origin == .own && hasFinishedRequiredQuestions {
            // Pull the latest streak before the celebration so the count-up shows
            // the right number; the screen predicts today's increment on top.
            await viewModel.refreshStreak()
            celebrate()
        } else if let next = nextAnswerableIndex(after: boundedIndex) {
            withAnimation(PaeoniaMotion.stateChange) { index = next }
        } else {
            await viewModel.refreshStreak()
            celebrate()
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
    private func goToRequiredStep(_ step: Int) {
        guard
            step >= 0,
            step < requiredQuestions.count,
            let questionIndex = questions.firstIndex(where: { $0.id == requiredQuestions[step].id }),
            questionIndex != boundedIndex
        else { return }
        isComposerFocused = false
        withAnimation(PaeoniaMotion.stateChange) { index = questionIndex }
    }

    private func nextAnswerableIndex(after current: Int) -> Int? {
        answerableIndices.first(where: { $0 > current }) ?? answerableIndices.first
    }

    private func nextRequiredAnswerableIndex(after current: Int) -> Int? {
        answerableRequiredIndices.first(where: { $0 > current }) ?? answerableRequiredIndices.first
    }

    private func setInitialIndexIfNeeded() {
        guard !didSetInitialIndex, !questions.isEmpty else { return }
        didSetInitialIndex = true
        if let first = nextRequiredAnswerableIndex(after: -1) {
            index = first
        } else if let firstRequiredQuestion = requiredQuestions.first,
                  let first = questions.firstIndex(where: { $0.id == firstRequiredQuestion.id }) {
            index = first
        } else if let first = nextAnswerableIndex(after: -1) {
            index = first
        }
    }

    /// Turns the screen over to the streak celebration. The haptics are deliberately
    /// left to `PaeoniaStreakFlame`, which owns the full crescendo — soft ticks rising
    /// with the count, then a firm payoff as the flame fills. Firing a success here too
    /// would pre-empt that build (and would be wrong for a slipped streak, which the
    /// flame keeps silent).
    private func celebrate() {
        isComposerFocused = false
        withAnimation(celebrateAnimation) { didCelebrate = true }
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

// MARK: - One question

/// One question's prompt + composer, shared by the daily challenge flow and the
/// Questions-tab partner-answer flow.
struct DailyChallengeAnswerStep: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        // The question always sits at the top. The answer-method picker is pinned
        // right under it, so its position never shifts with the composer. The actual
        // composer (text field, photo, voice, choice) drops to the bottom within
        // thumb reach; a keyboard just shrinks the gap, keeping the question on top.
        // The waiting hint reads as question context, so it stays up top too. Review
        // states have no bottom composer and sit under the question.
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            promptView

            if showsKindPicker {
                DailyAnswerKindPicker(
                    kinds: question.composableAnswerKinds,
                    selection: viewModel.composeKind(for: question),
                    onSelect: { viewModel.setComposeKind($0, for: question.id) }
                )
            }

            if showsPartnerWaitingNote {
                DailyPartnerWaitingNote(partnerName: viewModel.participants.partnerName)
            }

            if hasBottomComposer {
                Spacer(minLength: PaeoniaSpacing.space24)
            }

            answerSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space24)
        .padding(.bottom, PaeoniaSpacing.space8)
        .onAppear(perform: seedEditDraftIfNeeded)
    }

    /// The question text, sitting at the top of the step.
    private var promptView: some View {
        Text(question.prompt)
            .font(PaeoniaTypography.heroTitle)
            .foregroundStyle(.paeoniaTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The kind of composer currently on screen, or nil when the step is showing a
    /// review/sending state rather than an editable composer.
    private var activeComposerKind: DailyChallengeAnswerKind? {
        if viewModel.isSending(question.id) { return nil }
        if let editKind = question.editableAnswerKind { return editKind }
        if question.hasOwnAnswer { return nil }
        if question.canSubmitAnswer { return viewModel.composeKind(for: question) }
        return nil
    }

    /// Whether an input composer is on screen (compose or edit), so it should drop to
    /// the bottom for thumb reach. Review/sending states have none and sit up top.
    private var hasBottomComposer: Bool {
        activeComposerKind != nil
    }

    /// The answer-method picker shows only while composing a fresh answer that accepts
    /// more than one kind. It's pinned under the question so its position is stable
    /// regardless of which composer is selected.
    private var showsKindPicker: Bool {
        !viewModel.isSending(question.id)
            && question.editableAnswerKind == nil
            && !question.hasOwnAnswer
            && question.canSubmitAnswer
            && question.composableAnswerKinds.count > 1
            // Combined questions show both composers at once, so there's nothing to pick.
            && !question.usesCombinedCompose
    }

    /// Whether the partner's reply is waiting behind a fresh answer, so the "answer
    /// to see their reply" hint should show under the question.
    private var showsPartnerWaitingNote: Bool {
        !viewModel.isSending(question.id)
            && question.editableAnswerKind == nil
            && !question.hasOwnAnswer
            && question.canSubmitAnswer
            && question.partnerAnswer != nil
            && !question.canViewPartnerAnswer
    }

    @ViewBuilder
    private var answerSection: some View {
        if viewModel.isSending(question.id) {
            DailySendingAnswerView(
                mediaKind: question.mediaAnswerKind,
                mediaData: viewModel.sendingMediaData(for: question.id),
                voiceDurationMs: viewModel.sendingVoiceDurationMs(for: question.id),
                partnerChoiceName: viewModel.sendingPartnerChoiceName(for: question.id),
                text: viewModel.sendingText(for: question.id)
            )
        } else if let editKind = question.editableAnswerKind {
            editComposer(kind: editKind)
        } else if question.hasOwnAnswer {
            DailyQuestionStatusView(question: question, participants: viewModel.participants)
            DailyAnswerDetailsView(question: question, participants: viewModel.participants)
        } else if question.canSubmitAnswer {
            // Just the input here — the kind picker and the "answer to see their
            // reply" hint are pinned under the question in `body`, so only the
            // composer itself drops to the bottom for thumb reach.
            if question.usesCombinedCompose {
                combinedComposer
            } else {
                kindComposer
            }
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
                DailyQuestionStatusView(question: question, participants: viewModel.participants)

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

    /// For questions that accept text alongside a photo or partner pick, both
    /// composers show together — each optional — so the user can add one, the other,
    /// or both. The text field sits below so it lands just above the keyboard. While
    /// the field is focused the photo / partner pick folds away so the text composer
    /// owns the shorter height, and returns once the field is dismissed.
    @ViewBuilder
    private var combinedComposer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            if !isFocused.wrappedValue {
                combinedSecondaryComposer
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            DailyAnswerTextField(text: draftBinding, isFocused: isFocused)
        }
    }

    /// The non-text half of a combined question — a photo picker or partner pick —
    /// shown above the text field and hidden while the field is focused.
    @ViewBuilder
    private var combinedSecondaryComposer: some View {
        switch question.combinedSecondaryKind {
        case .photo:
            DailyPhotoAnswerComposer(
                imageData: viewModel.stagedMediaData(for: question.id),
                onPick: { viewModel.stagePhoto($0, for: question.id) },
                onRemove: { viewModel.removeStagedMedia(for: question.id) }
            )
        case .partnerChoice:
            if let options = viewModel.participants.partnerChoiceOptions {
                DailyPartnerChoicePicker(
                    options: options,
                    selection: viewModel.partnerChoiceSelection(for: question.id),
                    onSelect: { viewModel.setPartnerChoice($0, for: question.id) }
                )
            }
        default:
            EmptyView()
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
    let partnerName: String

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "lock.circle.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            Text(.dailyChallengePartnerHiddenMessage(partnerName))
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

/// The fixed bottom action bar, shared by the daily challenge flow and the
/// Questions-tab partner-answer flow. Skip is optional (off for partner answers).
struct DailyChallengeAnswerActionBar: View {
    let primaryTitle: LocalizedStringResource
    let isPrimaryBusy: Bool
    let isPrimaryDisabled: Bool
    /// Folds the primary button away while the keyboard is up, leaving just the
    /// Close/Skip row so the composer owns the shorter height. Dismissing the field
    /// (Close, or a tap outside) brings the button back so the answer can be sent.
    var hidesPrimary = false
    var canSkip = false
    var isSkipBusy = false
    var isSkipDisabled = false
    let onPrimary: () -> Void
    let onClose: () -> Void
    var onSkip: () -> Void = {}

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if !hidesPrimary {
                primaryButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
    }

    // Close sits on the left, Skip on the right, with a thin divider between them.
    // While the keyboard is up the left action becomes "Done": that's where the thumb
    // lands when the user finishes typing, and tapping it just puts the keyboard away
    // (one more tap, or the keyboard down, then leaves the screen).
    private var secondaryRow: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Label {
                    Text(hidesPrimary ? .dailyChallengeFlowDoneButton : .dailyChallengeFlowClose)
                        // Swap the label instantly. Without this the keyboard-show
                        // animation crossfades the two different-width strings, which
                        // reads as a glitchy flicker; the icon's symbol transition is
                        // clean, so only the text needs pinning.
                        .contentTransition(.identity)
                } icon: {
                    Image(systemName: hidesPrimary ? "keyboard.chevron.compact.down" : "xmark")
                        .accessibilityHidden(true)
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
    let streak: Int
    /// The partner's display name, so the finish copy and CTA name them.
    let partnerName: String
    /// The lost streak length when a restore is on offer; `nil` for a normal,
    /// celebratory finish. When set, the flame reads "slipped" and a "get it back"
    /// action is offered above Done.
    var restorableCount: Int?
    var onRestore: () -> Void = {}
    var hasPartnerQuestionsToAnswer = false
    var onOpenPartnerQuestions: () -> Void = {}
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Holds the supporting copy and actions back for a beat so the flame lands
    /// first, then lifts them in. The flame itself is always present so its count-up
    /// starts the instant the screen arrives.
    @State private var showDetails = false

    private var isRestorable: Bool { restorableCount != nil }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space32) {
            Spacer()

            PaeoniaStreakFlame(count: restorableCount ?? streak, isBroken: isRestorable)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.dailyChallengeFlowAllDoneTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(
                    isRestorable
                        ? .streakRestoreMessage
                        : .dailyChallengeFlowAllDoneMessage(partnerName)
                )
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .modifier(StreakDetailReveal(shown: showDetails))

            Spacer()

            actions
                .modifier(StreakDetailReveal(shown: showDetails))
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: revealDetails)
    }

    /// Lifts the copy and actions in shortly after the flame appears. Under Reduce
    /// Motion they are simply shown, with no delay or movement.
    private func revealDetails() {
        guard !showDetails else { return }
        if reduceMotion {
            showDetails = true
        } else {
            withAnimation(PaeoniaMotion.meaningfulMoment.delay(0.28)) {
                showDetails = true
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isRestorable {
            VStack(spacing: PaeoniaSpacing.space12) {
                Button(action: onRestore) {
                    Text(.streakRestoreTitle)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())

                partnerQuestionsButton(style: .secondary)

                Button(action: onDone) {
                    Text(.dailyChallengeFlowDoneButton)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            }
        } else if hasPartnerQuestionsToAnswer {
            VStack(spacing: PaeoniaSpacing.space12) {
                partnerQuestionsButton(style: .primary)

                Button(action: onDone) {
                    Text(.dailyChallengeFlowDoneButton)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            }
        } else {
            Button(action: onDone) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private func partnerQuestionsButton(style: PartnerQuestionsButtonStyle) -> some View {
        if hasPartnerQuestionsToAnswer {
            switch style {
            case .primary:
                Button(action: onOpenPartnerQuestions) {
                    Text(.dailyChallengeFlowPartnerQuestionsButton(partnerName))
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
            case .secondary:
                Button(action: onOpenPartnerQuestions) {
                    Text(.dailyChallengeFlowPartnerQuestionsButton(partnerName))
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        }
    }

    private enum PartnerQuestionsButtonStyle {
        case primary
        case secondary
    }
}

/// Fades and lifts the streak screen's supporting copy and actions in after the
/// flame has landed. Toggling `shown` (animated by the caller) plays the entrance;
/// the small offset gives the content a gentle rise rather than a flat fade.
private struct StreakDetailReveal: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : PaeoniaSpacing.space12)
    }
}

#if DEBUG
#Preview {
    DailyChallengeAnswerFlowPreviewHost()
}

#Preview("Completion") {
    DailyChallengeCompletionView(streak: 7, partnerName: "Oda", restorableCount: nil, onDone: {})
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Completion · streak slipped") {
    DailyChallengeCompletionView(streak: 1, partnerName: "Oda", restorableCount: 30, onRestore: {}, onDone: {})
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
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
