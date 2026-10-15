import SwiftUI

/// A short-lived snapshot of what the answer cover was already showing when the user
/// tapped Send. The view model clears the durable draft as soon as the answer is
/// queued, so the cover keeps this visual copy just long enough for the transition to
/// the next question or streak screen.
struct DailyAnswerStepVisualHold: Equatable {
    let questionID: UUID
    let text: String
    let partnerChoiceUserID: UUID?
    let composeKind: DailyChallengeAnswerKind?
    let mediaData: Data?
    let voiceDurationMs: Int?

    @MainActor
    init(question: DailyChallengeQuestion, viewModel: DailyChallengeViewModel) {
        questionID = question.id
        text = viewModel.draftText(for: question.id)
        partnerChoiceUserID = viewModel.partnerChoiceSelection(for: question.id)
        composeKind = viewModel.composeKind(for: question)
        mediaData = viewModel.stagedMediaData(for: question.id)
        voiceDurationMs = viewModel.stagedVoiceDurationMs(for: question.id)
    }
}

/// One question's prompt + composer, shared by the daily challenge flow and the
/// Questions-tab partner-answer flow.
struct DailyChallengeAnswerStep: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var isFocused: FocusState<Bool>.Binding
    var visualHold: DailyAnswerStepVisualHold? = nil
    /// Top inset for the question. Defaults to a full screen-top clearance for flows
    /// where the question is the topmost element (the partner-answer flow). The
    /// multi-question flow passes a smaller value because the progress bar sits just
    /// above the question and already establishes the top spacing.
    var topPadding: CGFloat = PaeoniaSpacing.space24

    /// False while typing, folding away the combined-question secondary composer (see
    /// `combinedComposer`) and the question card's footer. A tap on the field folds
    /// them before focusing it (see `answerTextField`). They come back as the keyboard
    /// starts to close, on the keyboard's curve.
    @State private var showsSecondaryComposer = true

    var body: some View {
        Group {
            if isReviewing {
                // Sent answers can be taller than the screen (two photos), so the
                // review state scrolls and the card keeps its natural height.
                ScrollView {
                    content(sitsLow: false)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                content(sitsLow: true)
            }
        }
        .onAppear {
            seedEditDraftIfNeeded()
            showsSecondaryComposer = !isFocused.wrappedValue
        }
        .onDockedKeyboardChange { docked in
            setSecondaryComposerShown(!docked)
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            // A hardware keyboard sends no keyboard notifications, so leaving the
            // field brings the folded parts back here instead.
            if !focused { setSecondaryComposerShown(true) }
        }
    }

    /// While composing, the question card hugs its text and the card and composer
    /// (text field, photo, voice, choice) sit together at the bottom, within thumb
    /// reach. The waiting hint and the answer-method picker live at the bottom of the
    /// card, so the picker sits right above the composer it switches. Review states
    /// show the answers under the card instead.
    ///
    /// A combined question pins the card to the top instead, with the composer still
    /// at the bottom. Its photo or partner pick folds away as the keyboard rises, and a
    /// card resting on the composer would ride both moves at once and wobble. Pinned,
    /// the card stays still and only the field moves, with the keyboard.
    private func content(sitsLow: Bool) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            DailyQuestionCard(prompt: question.prompt, holdsPromptSize: !showsSecondaryComposer) {
                EmptyView()
            } footer: {
                // While typing, the keyboard takes most of the screen, so the footer
                // folds away and the question keeps the card's room to itself.
                if showsSecondaryComposer {
                    cardFooter
                        .transition(Self.foldTransition)
                }
            }
            .frame(maxHeight: sitsLow && question.usesCombinedCompose ? .infinity : nil, alignment: .top)

            answerSection
        }
        .frame(maxWidth: .infinity, maxHeight: sitsLow ? .infinity : nil, alignment: sitsLow ? .bottom : .top)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, PaeoniaSpacing.space8)
    }

    /// Showing an answer already sent and no longer editable, so nothing here needs
    /// the keyboard and the content may be taller than the screen.
    private var isReviewing: Bool {
        !showsSendingState && question.editableAnswerKind == nil && question.hasOwnAnswer
    }

    /// The card's bottom edge: the waiting hint when it applies, then the
    /// answer-method picker when the user can choose, and otherwise small icons for
    /// how this question is answered.
    private var cardFooter: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if showsPartnerWaitingNote {
                DailyPartnerWaitingNote(partnerName: viewModel.participants.partnerName)
            }

            if showsKindPicker {
                DailyAnswerKindPicker(
                    kinds: question.composableAnswerKinds,
                    selection: composeKind,
                    onSelect: setComposeKind
                )
            } else {
                DailyAnswerKindBadges(kinds: question.composableAnswerKinds)
            }
        }
    }

    /// The answer-method picker shows only while composing a fresh answer that accepts
    /// more than one kind. It sits at the bottom of the question card, so its position
    /// is stable regardless of which composer is selected.
    private var showsKindPicker: Bool {
        !showsSendingState
            && question.editableAnswerKind == nil
            && !question.hasOwnAnswer
            && question.canSubmitAnswer
            && question.composableAnswerKinds.count > 1
            // Combined questions show both composers at once, so there's nothing to pick.
            && !question.usesCombinedCompose
    }

    /// Whether the partner's reply is waiting behind a fresh answer, so the "answer
    /// to see their reply" hint should show at the bottom of the question card.
    private var showsPartnerWaitingNote: Bool {
        !showsSendingState
            && question.editableAnswerKind == nil
            && !question.hasOwnAnswer
            && question.canSubmitAnswer
            && question.partnerAnswer != nil
            && !question.canViewPartnerAnswer
    }

    @ViewBuilder
    private var answerSection: some View {
        if showsSendingState {
            DailySendingAnswerView(
                mediaKind: question.mediaAnswerKind,
                mediaData: viewModel.sendingMediaData(for: question.id),
                voiceDurationMs: viewModel.sendingVoiceDurationMs(for: question.id),
                partnerChoiceName: viewModel.sendingPartnerChoiceName(for: question.id),
                text: viewModel.sendingText(for: question.id),
                showsSendingStatus: viewModel.isHeldOnPhone(question.id)
            )
        } else if let editKind = question.editableAnswerKind {
            editComposer(kind: editKind)
        } else if question.hasOwnAnswer {
            DailyQuestionStatusView(question: question, participants: viewModel.participants)
            DailyAnswerDetailsView(question: question, participants: viewModel.participants)
        } else if question.canSubmitAnswer {
            // Just the input here. The kind picker and the "answer to see their
            // reply" hint live at the bottom of the question card, so only the
            // composer itself sits under it for thumb reach.
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
                        selection: partnerChoiceSelection,
                        onSelect: setPartnerChoice
                    )
                } else {
                    DailyAnswerDetailsView(question: question, participants: viewModel.participants)
                }
            }
        default:
            answerTextField
        }
    }

    /// Fades only, never slides: a slide pulls the picker up across the card and the
    /// progress bar. It fades out fast, before the field moves into its spot.
    private static let foldTransition = AnyTransition.asymmetric(
        insertion: .opacity,
        removal: .opacity.animation(PaeoniaMotion.buttonPress)
    )

    /// The photo or partner pick waits to fade back in until the field, sliding down
    /// with the keyboard, has passed the spot where it sits.
    private static let secondaryFoldTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionFast)),
        removal: .opacity.animation(PaeoniaMotion.buttonPress)
    )

    /// The text field, with a tap target over it while the fold is open. A tap folds
    /// the card footer and the photo or partner pick first and only then focuses the
    /// field, so the keyboard rises into a layout that already fits. Focusing first
    /// lets the keyboard push the still-tall content up past the progress bar before
    /// anything folds. VoiceOver skips the target and focuses the field directly.
    private var answerTextField: some View {
        DailyAnswerTextField(text: draftBinding, isFocused: isFocused)
            .overlay {
                if showsSecondaryComposer {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: focusAnswerField)
                        .accessibilityHidden(true)
                }
            }
    }

    private func focusAnswerField() {
        setSecondaryComposerShown(false)
        isFocused.wrappedValue = true
    }

    private func setSecondaryComposerShown(_ shown: Bool) {
        guard showsSecondaryComposer != shown else { return }
        withAnimation(PaeoniaMotion.keyboard) { showsSecondaryComposer = shown }
    }

    /// For questions that accept text alongside a photo or partner pick, both
    /// composers show together, each optional, so the user can add one, the other,
    /// or both. The text field sits below so it lands just above the keyboard. While
    /// the field is focused the photo / partner pick folds away so the text composer
    /// owns the shorter height, and returns once the field is dismissed. The card is
    /// pinned to the top and the field to the bottom (see `content`), so the fold
    /// moves neither of them.
    @ViewBuilder
    private var combinedComposer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            if showsSecondaryComposer {
                combinedSecondaryComposer
                    .transition(Self.secondaryFoldTransition)
            }

            answerTextField
        }
    }

    /// The non-text half of a combined question, a photo picker or partner pick. It
    /// shows above the text field and hides while the field is focused.
    @ViewBuilder
    private var combinedSecondaryComposer: some View {
        switch question.combinedSecondaryKind {
        case .photo:
            DailyPhotoAnswerComposer(
                imageData: stagedMediaData,
                isPreparing: viewModel.isPreparingPhoto(for: question.id),
                onPick: stagePhoto,
                onPickFailed: viewModel.photoPickFailed,
                onRemove: removeStagedMedia
            )
        case .partnerChoice:
            if let options = viewModel.participants.partnerChoiceOptions {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    Label {
                        Text(.dailyChallengeCombinedChoiceHint)
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)

                    DailyPartnerChoicePicker(
                        options: options,
                        selection: partnerChoiceSelection,
                        onSelect: setPartnerChoice
                    )
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var kindComposer: some View {
        switch composeKind {
        case .partnerChoice:
            if let options = viewModel.participants.partnerChoiceOptions {
                DailyPartnerChoicePicker(
                    options: options,
                    selection: partnerChoiceSelection,
                    onSelect: setPartnerChoice
                )
            } else {
                DailyUnsupportedAnswerMessage(answerKinds: question.answerKinds)
            }
        case .photo:
            DailyPhotoAnswerComposer(
                imageData: stagedMediaData,
                isPreparing: viewModel.isPreparingPhoto(for: question.id),
                onPick: stagePhoto,
                onPickFailed: viewModel.photoPickFailed,
                onRemove: removeStagedMedia
            )
        case .voice:
            voiceComposer
        default:
            answerTextField
        }
    }

    @ViewBuilder
    private var voiceComposer: some View {
        if let voiceData = stagedMediaData {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(.dailyChallengeVoiceLabel)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)

                DailyVoicePlaybackView(
                    source: .data(voiceData),
                    fallbackDurationMs: voiceDurationMs
                )

                Button {
                    removeStagedMedia()
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
                    stageVoice(url: url, durationMs: durationMs)
                }
            )
        }
    }

    private var showsSendingState: Bool {
        visualHold == nil && viewModel.isSending(question.id)
    }

    private var composeKind: DailyChallengeAnswerKind? {
        visualHold?.composeKind ?? viewModel.composeKind(for: question)
    }

    private var partnerChoiceSelection: UUID? {
        visualHold?.partnerChoiceUserID ?? viewModel.partnerChoiceSelection(for: question.id)
    }

    private var stagedMediaData: Data? {
        visualHold?.mediaData ?? viewModel.stagedMediaData(for: question.id)
    }

    private var voiceDurationMs: Int? {
        visualHold?.voiceDurationMs ?? viewModel.stagedVoiceDurationMs(for: question.id)
    }

    private func setPartnerChoice(_ userID: UUID?) {
        guard visualHold == nil else { return }
        viewModel.setPartnerChoice(userID, for: question.id)
    }

    private func setComposeKind(_ kind: DailyChallengeAnswerKind) {
        guard visualHold == nil else { return }
        viewModel.setComposeKind(kind, for: question.id)
    }

    private func stagePhoto(_ imageData: Data) {
        guard visualHold == nil else { return }
        let questionID = question.id
        Task { await viewModel.stagePhoto(imageData, for: questionID) }
    }

    private func stageVoice(url: URL, durationMs: Int) {
        guard visualHold == nil else { return }
        viewModel.stageVoice(url: url, durationMs: durationMs, for: question.id)
    }

    private func removeStagedMedia() {
        guard visualHold == nil else { return }
        viewModel.removeStagedMedia(for: question.id)
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
            get: { visualHold?.text ?? viewModel.draftText(for: question.id) },
            set: {
                guard visualHold == nil else { return }
                viewModel.setDraftText($0, for: question.id)
            }
        )
    }
}

struct DailyPartnerWaitingNote: View {
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
        // Darker than the question card it sits in, so it reads as its own note.
        .background(.paeoniaBackgroundSecondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
    }
}
