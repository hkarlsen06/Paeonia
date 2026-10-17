import SwiftUI

/// The second page of profile setup: when the couple got together.
///
/// Continue saves the date, then counts up the days together right on this page.
/// Finishing profile setup moves the app on to the next screen, so it waits until the
/// count has landed. "Skip for now" finishes without a date. If finishing fails, the
/// count stays and Continue tries again.
struct AuthOnboardingStartDatePage: View {
    /// The profile save is running.
    let isSaving: Bool
    let onBack: () -> Void
    /// Saves the date. Returns false to stay on the page.
    let onSaveDate: (Date) async -> Bool
    /// Finishes profile setup.
    let onFinish: () -> Void

    @State private var selectedDate = Date()
    @State private var phase = Phase.picking
    @State private var isSavingDate = false
    /// Finishing after the count failed, so Continue shows to try again.
    @State private var finishFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case picking
        /// The count-up plays. Profile setup finishes once it lands.
        case revealing(startedOn: String)
        /// The count landed and profile setup was asked to finish.
        case revealed(startedOn: String)
    }

    var body: some View {
        ZStack {
            switch phase {
            case .picking:
                pickingPage
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            case let .revealing(startedOn), let .revealed(startedOn):
                revealPage(startedOn: startedOn)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: phase)
    }

    // MARK: Picking

    private var pickingPage: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space20) {
                backButton
                    .screenEntrance(order: 0)

                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(.homeMilestoneEditorSetupTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text(.onboardingStartDateMessage)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .screenEntrance(order: 1)

                datePicker
                    .screenEntrance(order: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, PaeoniaSpacing.space24)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaBottomBar(spacing: 0) {
            VStack(spacing: PaeoniaSpacing.space4) {
                Button(action: saveDate) {
                    Text(.authOnboardingCompleteButton)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isSavingDate))
                .accessibilityIdentifier("auth.onboarding.startDate.continue")

                Button(action: onFinish) {
                    Text(.onboardingStartDateSkipButton)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .accessibilityIdentifier("auth.onboarding.startDate.skip")
            }
            .disabled(isSavingDate || isSaving)
            .padding(.top, PaeoniaSpacing.space12)
            .screenEntrance(order: 3)
            .onboardingBottomBarFade()
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label {
                Text(.onboardingStartDateBackButton)
            } icon: {
                Image(systemName: "chevron.left")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isSavingDate || isSaving)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("auth.onboarding.startDate.back")
    }

    private var datePicker: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)

        return DatePicker(
            selection: $selectedDate,
            in: ...Date(),
            displayedComponents: .date
        ) {
            Text(.homeMilestoneEditorDateLabel)
        }
        .datePickerStyle(.graphical)
        .tint(.paeoniaAccentPrimary)
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfacePrimary, in: shape)
        .overlay {
            shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
        }
        .onChange(of: selectedDate) { _, _ in
            PaeoniaHaptics.selection()
            GameSound.tick.play(volume: 0.4)
        }
    }

    // MARK: Reveal

    private func revealPage(startedOn: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            RelationshipDaysReveal(startedOn: startedOn) {
                guard phase == .revealing(startedOn: startedOn) else {
                    return
                }
                phase = .revealed(startedOn: startedOn)
                onFinish()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paeoniaBottomBar(spacing: 0) {
            // Only needed when finishing failed. Otherwise the page moves on by itself.
            if finishFailed {
                Button(action: retryFinish) {
                    Text(.authOnboardingCompleteButton)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isSaving))
                .padding(.top, PaeoniaSpacing.space12)
                .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: finishFailed)
        // A finished save moves the app on, so a save that ends while this page
        // still shows has failed.
        .onChange(of: isSaving) { wasSaving, isSaving in
            if wasSaving, !isSaving, case .revealed = phase {
                finishFailed = true
            }
        }
    }

    // MARK: Actions

    private func retryFinish() {
        guard !isSaving else {
            return
        }
        onFinish()
    }

    private func saveDate() {
        guard !isSavingDate, !isSaving else {
            return
        }
        isSavingDate = true
        let date = selectedDate
        Task {
            let saved = await onSaveDate(date)
            isSavingDate = false
            guard saved else {
                return
            }
            PaeoniaHaptics.profileSetupSent()
            phase = .revealing(startedOn: PairingStartDate(date: date).rawValue)
        }
    }
}

#if DEBUG
#Preview {
    RootBrandedFrame {
        AuthOnboardingStartDatePage(
            isSaving: false,
            onBack: {},
            onSaveDate: { _ in true },
            onFinish: {}
        )
    }
    .preferredColorScheme(.dark)
}
#endif
