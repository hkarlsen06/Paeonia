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
    var visualHold: DailyAnswerStepVisualHold?
    /// Top inset for the question. Defaults to a full screen-top clearance for flows
    /// where the question is the topmost element (the partner-answer flow). The
    /// multi-question flow passes a smaller value because the progress bar sits just
    /// above the question and already establishes the top spacing.
    var topPadding: CGFloat = PaeoniaSpacing.space24
    /// A small overline over the question, such as the topic's name.
    var eyebrow: String?

    /// False while typing, folding away the combined-question secondary composer (see
    /// `combinedComposer`) and the question card's footer. A tap on the field folds
    /// them before focusing it (see `answerTextField`). They come back as the keyboard
    /// starts to close, on the keyboard's curve.
    @State var showsSecondaryComposer = true
    @Environment(\.scenePhase) private var scenePhase

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
        // Typed text is saved after a short pause. Save it now when this screen
        // goes away or the app leaves the foreground.
        .onDisappear { viewModel.flushDraftPersistence() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.flushDraftPersistence() }
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
                if let eyebrow {
                    Text(verbatim: eyebrow)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
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
            } else if showsGoesFirstNote {
                DailyPartnerWaitingNote(
                    partnerName: viewModel.participants.partnerName,
                    message: .topicsFlowYouGoFirst(viewModel.participants.partnerName)
                )
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
    /// A topic question nobody has answered: the partner sees this answer only after
    /// answering too.
    private var showsGoesFirstNote: Bool {
        question.isTopicQuestion
            && !showsSendingState
            && !question.hasOwnAnswer
            && question.partnerAnswer == nil
    }

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
    private var showsSendingState: Bool {
        visualHold == nil && viewModel.isSending(question.id)
    }

    var composeKind: DailyChallengeAnswerKind? {
        visualHold?.composeKind ?? viewModel.composeKind(for: question)
    }

    var partnerChoiceSelection: UUID? {
        visualHold?.partnerChoiceUserID ?? viewModel.partnerChoiceSelection(for: question.id)
    }

    var stagedMediaData: Data? {
        visualHold?.mediaData ?? viewModel.stagedMediaData(for: question.id)
    }

    var voiceDurationMs: Int? {
        visualHold?.voiceDurationMs ?? viewModel.stagedVoiceDurationMs(for: question.id)
    }

    func setPartnerChoice(_ userID: UUID?) {
        guard visualHold == nil else { return }
        viewModel.setPartnerChoice(userID, for: question.id)
    }

    private func setComposeKind(_ kind: DailyChallengeAnswerKind) {
        guard visualHold == nil else { return }
        viewModel.setComposeKind(kind, for: question.id)
    }

    func stagePhoto(_ imageData: Data) {
        guard visualHold == nil else { return }
        let questionID = question.id
        Task { await viewModel.stagePhoto(imageData, for: questionID) }
    }

    func stageVoice(url: URL, durationMs: Int) {
        guard visualHold == nil else { return }
        viewModel.stageVoice(url: url, durationMs: durationMs, for: question.id)
    }

    func removeStagedMedia() {
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

    var draftBinding: Binding<String> {
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
    /// Defaults to "answer to unlock their answer".
    var message: LocalizedStringResource?

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "lock.circle.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            Text(message ?? .dailyChallengePartnerHiddenMessage(partnerName))
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
