import SwiftUI

/// The first step of starting a couple, before sign-in: when the couple got together.
///
/// Continue saves the date on this phone, then counts up the days together right on this
/// step and moves on once the count has landed. "Skip for now" moves on without a date.
/// The Home milestone card asks couples without a date later.
struct WelcomeStartDateStep: View {
    let onBack: () -> Void
    let onSave: (Date) -> Void
    let onSkip: () -> Void
    /// The count landed.
    let onFinish: () -> Void

    @State private var selectedDate = Date()
    @State private var revealedStartedOn: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let revealedStartedOn {
                revealPage(startedOn: revealedStartedOn)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else {
                pickingPage
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: revealedStartedOn)
    }

    // MARK: Picking

    private var pickingPage: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space20) {
                WelcomeBackButton(action: onBack)
                    .accessibilityIdentifier("welcome.startDate.back")
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
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .accessibilityIdentifier("welcome.startDate.continue")

                Button(action: onSkip) {
                    Text(.onboardingStartDateSkipButton)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .accessibilityIdentifier("welcome.startDate.skip")
            }
            .padding(.top, PaeoniaSpacing.space12)
            .screenEntrance(order: 3)
            .onboardingBottomBarFade()
        }
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
            RelationshipDaysReveal(startedOn: startedOn, onFinished: onFinish)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveDate() {
        guard revealedStartedOn == nil else {
            return
        }
        onSave(selectedDate)
        PaeoniaHaptics.profileSetupSent()
        revealedStartedOn = PairingStartDate(date: selectedDate).rawValue
    }
}

/// The quiet "Back" link at the top of a signed-out step.
struct WelcomeBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(.onboardingStartDateBackButton)
            } icon: {
                Image(systemName: "chevron.left")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    RootBrandedFrame {
        WelcomeStartDateStep(onBack: {}, onSave: { _ in }, onSkip: {}, onFinish: {})
    }
    .preferredColorScheme(.dark)
}
#endif
