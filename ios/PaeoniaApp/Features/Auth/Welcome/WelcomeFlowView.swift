import SwiftUI

/// The signed-out flow: welcome, then the start date and the first drawing for someone
/// starting a couple, then sign-in. Steps crossfade, and every step after welcome sits in
/// `RootBrandedFrame`, with the lockup where the welcome screen draws its own, so the logo
/// stays still. The drawing screen fills the screen. A fade only, so Reduce Motion needs
/// no branch.
struct WelcomeFlowView: View {
    let model: WelcomeFlowModel
    let isWorking: Bool
    let signingInWith: AuthProvider?
    let pendingInviteCode: String?
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    /// Saves a partner's invite code, which moves the flow to sign-in for joining.
    let onSubmitInviteCode: (String) -> Void
    let onForgetInviteCode: () -> Void

    var body: some View {
        ZStack {
            stepView
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: model.step)
        // A code from the welcome step, the sign-in step, or an invite link.
        .onAppear {
            if pendingInviteCode != nil {
                model.inviteCodeSaved()
            }
        }
        .onChange(of: pendingInviteCode) { _, code in
            if code != nil {
                model.inviteCodeSaved()
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome:
            WelcomeView(model: model, onSubmitInviteCode: onSubmitInviteCode)
                .transition(.opacity)
        case .startDate:
            RootBrandedFrame {
                WelcomeStartDateStep(
                    onBack: back,
                    onSave: model.saveStartDate,
                    onSkip: model.skipStartDate,
                    onFinish: model.finishStartDate
                )
            }
            .transition(.opacity)
        case .drawing:
            WelcomeDrawingStep(model: model)
                .transition(.opacity)
        case let .signIn(mode):
            RootBrandedFrame {
                WelcomeSignInStep(
                    mode: mode,
                    isWorking: isWorking,
                    signingInWith: signingInWith,
                    onBack: back,
                    onAppleSignIn: onAppleSignIn,
                    onGoogleSignIn: onGoogleSignIn,
                    onSubmitInviteCode: onSubmitInviteCode,
                    onAppear: model.signInAppeared,
                    loadDrawing: model.waitingDrawingImage
                )
            }
            .transition(.opacity)
        }
    }

    private func back() {
        model.back(onForgetInviteCode: onForgetInviteCode)
    }
}
