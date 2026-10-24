import SwiftUI

/// "When should your questions arrive?" Picking a concrete moment, like the morning
/// coffee, makes the habit easier to keep, so each choice names one. The primary
/// button repeats the time ("Remind me at 20:00"), saves the reminder and then asks
/// iOS for notification permission. "Not now" finishes without saving.
///
/// A failed save shows the top banner and keeps the person here with their choice.
/// `onFinish` gets the saved minutes after midnight, or nil for "Not now".
struct QuestionTimeStep: View {
    let context: QuestionTimeStepContext
    let placement: OnboardingStepPlacement
    let onFinish: (_ chosenMinutes: Int?) -> Void

    @State private var model: QuestionTimeModel
    @State private var hasFinished = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var bellSize: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var choiceIconWidth: CGFloat = 28

    init(
        context: QuestionTimeStepContext,
        placement: OnboardingStepPlacement = .screenFrame,
        model: QuestionTimeModel = QuestionTimeModel(),
        onFinish: @escaping (_ chosenMinutes: Int?) -> Void
    ) {
        self.context = context
        self.placement = placement
        self.onFinish = onFinish
        _model = State(initialValue: model)
    }

    var body: some View {
        OnboardingStepScaffold(
            title: .onboardingQuestionTimeTitle,
            message: message,
            placement: placement,
            primary: OnboardingStepAction(
                title: .onboardingQuestionTimeRemindButton(Self.timeText(model.chosenMinutes)),
                isLoading: model.isSaving,
                action: save
            ),
            secondary: OnboardingStepAction(
                title: .onboardingQuestionTimeNotNowButton,
                isEnabled: !model.isSaving,
                action: skip
            ),
            // The time wheel opens under the choices, below the fold on most phones.
            scrollTarget: model.choice == .custom ? Self.customPickerID : nil
        ) {
            Image(systemName: "bell.fill")
                .font(.system(size: bellSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .symbolEffect(.bounce, value: model.choice)
                .accessibilityHidden(true)
        } content: {
            VStack(spacing: PaeoniaSpacing.space12) {
                ForEach(QuestionTimeChoice.allCases, id: \.self) { choice in
                    choiceRow(choice)
                }

                if model.choice == .custom {
                    customPicker
                        .id(Self.customPickerID)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(PaeoniaMotion.stateChange, value: model.choice)
            .disabled(model.isSaving)
        }
        .onChange(of: model.saveFailure) { _, failure in
            guard let failure else {
                return
            }
            bannerCenter.show(.error(
                title: String(localized: .onboardingQuestionTimeSaveFailedTitle),
                message: String(
                    localized: failure == .offline
                        ? .onboardingQuestionTimeSaveFailedOfflineMessage
                        : .commonActionFailedMessage
                )
            ))
            model.clearSaveFailure()
        }
    }

    private var message: LocalizedStringResource {
        switch context {
        case .waitingForPartner: .onboardingQuestionTimeMessageWaiting
        case .paired: .onboardingQuestionTimeMessagePaired
        }
    }

    // MARK: Choices

    private func choiceRow(_ choice: QuestionTimeChoice) -> some View {
        let isSelected = model.choice == choice
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return Button {
            select(choice)
        } label: {
            choiceLabel(choice, isSelected: isSelected)
                .padding(PaeoniaSpacing.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.paeoniaSurfacePrimary : Color.paeoniaSurfaceSecondary, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Color.paeoniaAccentPrimary : .clear,
                        lineWidth: PaeoniaRadius.strokeEmphasis
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The icon, the name and its moment, and the time. The parts stack at the
    /// largest text sizes.
    private func choiceLabel(_ choice: QuestionTimeChoice, isSelected: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))

        return layout {
            Image(systemName: Self.symbol(for: choice))
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .paeoniaAccentPrimary : .paeoniaTextSecondary)
                .frame(width: choiceIconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(Self.title(for: choice))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(Self.subtitle(for: choice))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let minutes = choice.presetMinutes ?? (isSelected ? model.customMinutes : nil) {
                Text(Self.timeText(minutes))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .paeoniaAccentPrimary : .paeoniaTextPrimary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var customPicker: some View {
        DatePicker(
            selection: Binding(
                get: { QuestionTimeReminder(minutes: model.customMinutes).time(on: Date()) },
                set: { model.customMinutes = QuestionTimeReminder.minutes(of: $0) }
            ),
            displayedComponents: .hourAndMinute
        ) {
            Text(.onboardingQuestionTimePickerLabel)
        }
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func select(_ choice: QuestionTimeChoice) {
        guard choice != model.choice else {
            return
        }
        PaeoniaHaptics.selection()
        GameSound.tick.play(volume: 0.4)
        model.select(choice)
    }

    private func save() {
        guard !hasFinished else {
            return
        }
        Task {
            guard let minutes = await model.save(), !hasFinished else {
                return
            }
            hasFinished = true
            // No sound here. The step that follows plays its own payoff right after.
            PaeoniaHaptics.questionTimeSaved()
            onFinish(minutes)
        }
    }

    private func skip() {
        guard !hasFinished, !model.isSaving else {
            return
        }
        hasFinished = true
        onFinish(nil)
    }

    private static let customPickerID = "questionTime.customPicker"

    // MARK: Copy

    /// The time in the phone's own format, such as 20:00 or 8:00 PM.
    private static func timeText(_ minutes: Int) -> String {
        QuestionTimeReminder(minutes: minutes)
            .time(on: Date())
            .formatted(date: .omitted, time: .shortened)
    }

    private static func symbol(for choice: QuestionTimeChoice) -> String {
        switch choice {
        case .morning: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .evening: "moon.stars.fill"
        case .custom: "clock.fill"
        }
    }

    private static func title(for choice: QuestionTimeChoice) -> LocalizedStringResource {
        switch choice {
        case .morning: .onboardingQuestionTimeMorningTitle
        case .lunch: .onboardingQuestionTimeLunchTitle
        case .evening: .onboardingQuestionTimeEveningTitle
        case .custom: .onboardingQuestionTimeCustomTitle
        }
    }

    private static func subtitle(for choice: QuestionTimeChoice) -> LocalizedStringResource {
        switch choice {
        case .morning: .onboardingQuestionTimeMorningSubtitle
        case .lunch: .onboardingQuestionTimeLunchSubtitle
        case .evening: .onboardingQuestionTimeEveningSubtitle
        case .custom: .onboardingQuestionTimeCustomSubtitle
        }
    }
}

#if DEBUG
// swiftlint:disable async_without_await
/// Saves after a short wait, or fails when `fails` is set, so the preview shows the
/// spinner and the banner.
nonisolated private struct PreviewQuestionTimePreferences: NotificationPreferencesProviding {
    var fails = false

    func loadNotificationPreferences() async throws -> NotificationPreferences {
        NotificationPreferences()
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws {}

    func setQuestionTimeReminder(_ reminder: QuestionTimeReminder) async throws {
        try await Task.sleep(for: .seconds(1))
        if fails {
            throw URLError(.notConnectedToInternet)
        }
    }
}

nonisolated private struct PreviewPushAuthorization: PushAuthorizationProviding {
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func isDenied() async -> Bool { false }
}
// swiftlint:enable async_without_await

private struct QuestionTimeStepPreview: View {
    let context: QuestionTimeStepContext
    var fails = false

    @State private var bannerCenter = PaeoniaBannerCenter()

    var body: some View {
        QuestionTimeStep(
            context: context,
            placement: .standalone,
            model: QuestionTimeModel(
                preferences: PreviewQuestionTimePreferences(fails: fails),
                pushAuthorization: PreviewPushAuthorization(),
                primerStore: UserDefaultsPushPermissionPrimerStore(
                    defaults: UserDefaults(suiteName: "QuestionTimeStepPreview") ?? .standard
                )
            ),
            onFinish: { _ in }
        )
        .environment(bannerCenter)
        .paeoniaTopBanner(bannerCenter)
        .preferredColorScheme(.dark)
    }
}

#Preview("Waiting for partner") {
    QuestionTimeStepPreview(context: .waitingForPartner)
}

#Preview("Paired, save fails offline") {
    QuestionTimeStepPreview(context: .paired, fails: true)
}
#endif
