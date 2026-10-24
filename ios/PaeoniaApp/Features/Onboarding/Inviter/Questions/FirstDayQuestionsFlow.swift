import SwiftUI

/// The inviter answers their first question before the partner joins, on a page like
/// the daily answer flow's. Then it asks when questions should arrive, unless the
/// reminder is on already, and ends on a small finish. Shown as a full-screen cover
/// from the invite screen. `onClose` gets the question with its saved answer.
struct FirstDayQuestionsFlow: View {
    @Bindable var model: FirstDayQuestionsModel
    let onClose: (FirstDayQuestion) -> Void

    @FocusState private var isComposerFocused: Bool
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.step {
            case .question:
                questionPage
                    .transition(pageTransition)
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

    private var questionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                closeButton

                DailyQuestionCard(prompt: model.question.prompt(for: .current)) {
                    EmptyView()
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

                DailyAnswerTextField(text: composerText, isFocused: $isComposerFocused)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        // Rides above the keyboard like the daily answer flow's bar, so Done is in
        // reach while typing.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            continueButton
        }
    }

    /// Ignores typing while the answer saves, without disabling the field, so the
    /// keyboard stays up if the save fails.
    private var composerText: Binding<String> {
        Binding(
            get: { model.text },
            set: { newValue in
                if !model.isSaving {
                    model.text = newValue
                }
            }
        )
    }

    private var continueButton: some View {
        Button(action: continueFromQuestion) {
            Text(.dailyChallengeFlowDoneButton)
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
            isComposerFocused = false
        }
    }

    private func close() {
        isComposerFocused = false
        onClose(model.question)
    }
}

/// The last page: the answer is saved for the partner. A heart burst rises from the
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
    let gateway = DeveloperFirstDayGateway(answered: false)
    FirstDayQuestionsFlow(
        model: FirstDayQuestionsModel(
            question: FirstDayQuestion(
                questionVersionID: UUID(),
                promptEN: "What is one small thing your partner did recently that stayed with you?",
                promptNB: "Hva er en liten ting partneren din gjorde nylig som har blitt værende hos deg?"
            ),
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
