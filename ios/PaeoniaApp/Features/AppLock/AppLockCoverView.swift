import SwiftUI

/// What the cover window shows. It continues the launch screen (the petal mark
/// centered on plum, in the same place), so opening a locked app has no jump.
/// The controls appear only when the app is locked. A shield for the app
/// switcher is the mark alone.
struct AppLockCoverView: View {
    let model: AppLockModel

    var body: some View {
        ZStack {
            // Centered on the full screen like the system launch screen.
            ZStack {
                Color.paeoniaBackgroundPrimary
                Image(.paeoniaLaunchPetalMark)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()

            if model.isLocked {
                controls
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.isLocked)
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            Spacer()

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.appLockTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                if model.lastUnlockFailed {
                    Text(.appLockUnlockFailed)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .multilineTextAlignment(.center)

            Button {
                Task { await model.unlock() }
            } label: {
                Label {
                    Text(.appLockUnlockButton(model.capability.biometry.name))
                } icon: {
                    Image(systemName: model.capability.biometry.systemImage)
                }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: model.isAuthenticating))
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space24)
    }
}

#if DEBUG
#Preview("Locked") {
    AppLockCoverView(model: AppLockModel(
        store: UserDefaultsAppLockStore(defaults: UserDefaults(suiteName: "AppLockPreview") ?? .standard),
        authenticator: LocalAuthenticationAppLockAuthenticator()
    ))
}
#endif
