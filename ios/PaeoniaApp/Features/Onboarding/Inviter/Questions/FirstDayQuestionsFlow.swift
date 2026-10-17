import SwiftUI

/// The inviter answers their two first questions before the partner joins, one page
/// each, like the daily answer flow. Then it asks when questions should arrive, unless
/// the reminder is on already, and ends on a small finish. Shown as a full-screen cover
/// from the invite screen. `onClose` gets the questions with their saved answers.
struct FirstDayQuestionsFlow: View {
    @Bindable var model: FirstDayQuestionsModel
    let onClose: ([FirstDayQuestion]) -> Void

    @FocusState private var isComposerFocused: Bool
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.step {
            case let .question(index):
                if model.questions.indices.contains(index) {
                    questionPage(model.questions[index], index: index)
                        .id(index)
                        .transition(pageTransition)
                }
            case .questionTime:
                QuestionTimeStep(
                    context: .waitingForPartner,
                    placement: .standalone,
                    model: model.questionTimeModel
                ) { _ in
                    model.finishQuestionTime()
                }
                .transition(pageTransition)
            case .finished:
                FirstDayQuestionsFinish(onDone: close)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PaeoniaGlowBackground() }
        .animation(
            reduceMotion ? .easeInOut(duration: PaeoniaMotion.motionDefault) : PaeoniaMotion.cardReveal,
            value: model.step
        )
        .task {
            await model.loadQuestionTimeState()
        }
        .onChange(of: model.saveFailure) { _, failure in
            guard let failure else {
                return
            }
            bannerCenter.show(.error(
                title: String(localized: .firstDayQuestionsSaveFailedTitle),
                message: String(
                    localized: failure == .offline
                        ? .firstDayQuestionsSaveFailedOfflineMessage
                        : .commonActionFailedMessage
                )
            ))
            model.clearSaveFailure()
        }
    }

    /// The next page comes in from the trailing edge. Reduce Motion crossfades.
    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    // MARK: Question page

    private func questionPage(_ question: FirstDayQuestion, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                closeButton

                DailyQuestionCard(prompt: question.prompt(for: .current)) {
                    Text(.firstDayQuestionsEyebrow(index + 1, model.questions.count))
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(.paeoniaAccentPrimary)
                } footer: {
                    Label {
                        Text(.firstDayQuestionsRevealRule)
                    } icon: {
                        Image(systemName: "lock.fill")
                            .accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                DailyAnswerTextField(text: composerText(for: question), isFocused: $isComposerFocused)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        // Rides above the keyboard like the daily answer flow's bar, so Next is in
        // reach while typing.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            continueButton
        }
    }

    /// Ignores typing while the answer saves, without disabling the field. A disabled
    /// field drops the keyboard, which would then have to come back for the next page.
    /// Reads the page's own question, so the page keeps its text while it slides out.
    private func composerText(for question: FirstDayQuestion) -> Binding<String> {
        Binding(
            get: { model.text(for: question) },
            set: { newValue in
                if !model.isSaving, model.currentQuestion?.id == question.id {
                    model.text = newValue
                }
            }
        )
    }

    private var continueButton: some View {
        Button(action: continueFromQuestion) {
            Text(model.isLastQuestion ? .dailyChallengeFlowDoneButton : .dailyChallengeFlowNextButton)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: model.isSaving))
        .disabled(!model.canContinue)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
        .accessibilityIdentifier("firstDay.questions.continue")
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .background(.paeoniaSurfaceSecondary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityLabel(Text(.commonClose))
    }

    // MARK: Actions

    private func continueFromQuestion() {
        Task {
            guard await model.continueFromQuestion() else {
                return
            }
            PaeoniaHaptics.firstDayAnswerSaved()
            GameSound.send.play(volume: 0.6)
            // The next page's field takes over the keyboard. After the last one it goes.
            isComposerFocused = model.currentQuestion != nil
        }
    }

    private func close() {
        isComposerFocused = false
        onClose(model.questions)
    }
}

/// The last page: the answers are saved for the partner. A heart burst rises from the
/// icon as it lands, with a chime.
private struct FirstDayQuestionsFinish: View {
    let onDone: () -> Void

    @State private var hasLanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Spacer(minLength: 0)

            Image(systemName: "text.bubble.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .symbolEffect(.bounce, value: hasLanded)
                .background {
                    if hasLanded {
                        MilestoneHeartBurst(unit: iconSize * 1.6)
                    }
                }
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.firstDayQuestionsDoneTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(.firstDayQuestionsDoneMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        .paeoniaBottomBar(spacing: 0) {
            Button(action: onDone) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space12)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .task {
            // A beat after the page arrives, so the burst lands on a still screen.
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.25))
            guard !Task.isCancelled else {
                return
            }
            hasLanded = true
            PaeoniaHaptics.answerRevealed()
            GameSound.chime.play()
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var bannerCenter = PaeoniaBannerCenter()
    let gateway = DeveloperFirstDayGateway(answered: 0)
    FirstDayQuestionsFlow(
        model: FirstDayQuestionsModel(
            questions: [
                FirstDayQuestion(
                    slotNumber: 1,
                    questionVersionID: UUID(),
                    promptEN: "What is one small thing your partner did recently that stayed with you?",
                    promptNB: "Hva er en liten ting partneren din gjorde nylig som har blitt værende hos deg?"
                ),
                FirstDayQuestion(
                    slotNumber: 2,
                    questionVersionID: UUID(),
                    promptEN: "What is one place you would like to show them?",
                    promptNB: "Hvilket sted har du lyst til å vise dem?"
                ),
            ],
            ownerUserID: UUID(),
            gateway: gateway,
            draftStore: UserDefaultsFirstDayAnswerDraftStore(
                defaults: UserDefaults(suiteName: "FirstDayQuestionsFlowPreview") ?? .standard
            ),
            preferences: DeveloperNotificationPreferences()
        ),
        onClose: { _ in }
    )
    .environment(bannerCenter)
    .paeoniaTopBanner(bannerCenter)
    .preferredColorScheme(.dark)
}
#endif
