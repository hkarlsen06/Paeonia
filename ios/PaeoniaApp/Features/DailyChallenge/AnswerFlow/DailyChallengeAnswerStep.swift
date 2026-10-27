import SwiftUI

/// Keeps the composer filled while its saved answer opens in the conversation.
struct DailyAnswerStepVisualHold: Equatable {
    let questionID: UUID
    let text: String
    let partnerChoiceUserID: UUID?
    let composeKind: DailyChallengeAnswerKind?
    let mediaData: Data?
    let voiceDurationMs: Int?
    let optionChoice: DailyAnswerOption?

    @MainActor
    init(question: DailyChallengeQuestion, viewModel: DailyChallengeViewModel) {
        questionID = question.id
        text = viewModel.draftText(for: question.id)
        partnerChoiceUserID = viewModel.partnerChoiceSelection(for: question.id)
        composeKind = viewModel.composeKind(for: question)
        mediaData = viewModel.stagedMediaData(for: question.id)
        voiceDurationMs = viewModel.stagedVoiceDurationMs(for: question.id)
        optionChoice = viewModel.optionChoiceSelection(for: question.id)
    }
}

/// The prompt and one answer composer, shared by daily and topic questions.
struct DailyChallengeAnswerStep: View {
    let question: DailyChallengeQuestion
    let viewModel: DailyChallengeViewModel
    var isFocused: FocusState<Bool>.Binding
    var visualHold: DailyAnswerStepVisualHold?
    var eyebrow: String?
    var isSubmitting = false
    var isSubmitDisabled = false
    var onSubmit: () -> Void = {}

    @State var isKeyboardPresented = false
    @State var isRecording = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .title) private var questionSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title2) private var compactQuestionSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var smallQuestionSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            questionContent

            composer
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space16)
        .padding(.bottom, PaeoniaSpacing.space12)
        .onAppear { isKeyboardPresented = isFocused.wrappedValue }
        .onDisappear { viewModel.flushDraftPersistence() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.flushDraftPersistence() }
        }
        .onDockedKeyboardChange { docked in
            isKeyboardPresented = docked
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            if focused { isKeyboardPresented = true }
            else { isKeyboardPresented = false }
        }
    }

    private var questionContent: some View {
        ViewThatFits(in: .vertical) {
            questionHeader(size: isKeyboardPresented ? compactQuestionSize : questionSize)
            questionHeader(size: min(compactQuestionSize, smallQuestionSize))
            ScrollView {
                questionHeader(size: min(compactQuestionSize, smallQuestionSize))
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dismissesKeyboardOnTap { isFocused.wrappedValue = false }
    }

    private func questionHeader(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Group {
                if let eyebrow {
                    Text(verbatim: eyebrow)
                } else {
                    Text(.homeDailyPromptEyebrow)
                }
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.paeoniaTextSecondary)
            Text(verbatim: question.prompt)
                .font(.system(size: size, weight: .medium, design: .serif))
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("daily.answer.question")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            composerContent
            .padding(PaeoniaSpacing.space16)
            .environment(\.dailyAnswerComposerColors, .composer)
            .background(.paeoniaSurfacePrimary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20)
                    .strokeBorder(.paeoniaAccentPrimary.opacity(0.14), lineWidth: PaeoniaRadius.strokeHairline)
            }
            .tint(.paeoniaAccentPrimary)

            if !isKeyboardPresented {
                Text(.dailyChallengeComposerSharingNote)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if !isKeyboardPresented {
                Text(.dailyChallengeTextAnswerLabel)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(DailyAnswerComposerColors.composer.secondary)
            }
            if !question.usesCombinedCompose && question.composableAnswerKinds.count > 1 {
                DailyAnswerKindPicker(
                    kinds: question.composableAnswerKinds,
                    selection: composeKind,
                    onSelect: setComposeKind
                )
            }
            if question.usesCombinedCompose {
                combinedComposer
            } else {
                kindComposer
            }
            composerFooter
        }
    }

    private var composerFooter: some View {
        HStack {
            if isKeyboardPresented {
                Button {
                    isFocused.wrappedValue = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DailyAnswerComposerColors.composer.secondary)
                .accessibilityLabel(Text(.dailyChallengeFlowDoneButton))
            }
            Spacer(minLength: PaeoniaSpacing.space8)
            DailyAnswerComposerSendButton(
                title: .dailyChallengeSubmitButton,
                isBusy: isSubmitting,
                isDisabled: isSubmitDisabled || isRecording,
                onSend: onSubmit
            )
        }
    }

    var composeKind: DailyChallengeAnswerKind? {
        visualHold?.composeKind ?? viewModel.composeKind(for: question)
    }

    var partnerChoiceSelection: UUID? {
        visualHold?.partnerChoiceUserID ?? viewModel.partnerChoiceSelection(for: question.id)
    }

    var optionChoiceSelection: DailyAnswerOption? {
        visualHold?.optionChoice ?? viewModel.optionChoiceSelection(for: question.id)
    }

    var stagedMediaData: Data? {
        visualHold?.mediaData ?? viewModel.stagedMediaData(for: question.id)
    }

    var voiceDurationMs: Int? {
        visualHold?.voiceDurationMs ?? viewModel.stagedVoiceDurationMs(for: question.id)
    }

    func setOptionChoice(_ option: DailyAnswerOption) {
        guard visualHold == nil else { return }
        viewModel.setOptionChoice(option, for: question.id)
    }

    func setPartnerChoice(_ userID: UUID?) {
        guard visualHold == nil else { return }
        viewModel.setPartnerChoice(userID, for: question.id)
    }

    func setComposeKind(_ kind: DailyChallengeAnswerKind) {
        guard visualHold == nil else { return }
        if kind != .text { isFocused.wrappedValue = false }
        viewModel.setComposeKind(kind, for: question.id)
    }

    func stagePhoto(_ imageData: Data) {
        guard visualHold == nil else { return }
        Task { await viewModel.stagePhoto(imageData, for: question.id) }
    }

    func stageVoice(url: URL, durationMs: Int) {
        guard visualHold == nil else { return }
        viewModel.stageVoice(url: url, durationMs: durationMs, for: question.id)
    }

    func removeStagedMedia() {
        guard visualHold == nil else { return }
        viewModel.removeStagedMedia(for: question.id)
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
