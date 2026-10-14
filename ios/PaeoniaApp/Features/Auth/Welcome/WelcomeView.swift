import SwiftUI

/// The signed-out entry screen. The lockup, one picture, and one line say what
/// Paeonia is, and the person can sign in right away. There is no carousel to
/// page through first. It is the first surface the cold-launch intro uncovers,
/// so its parts cascade in with `View.launchEntrance(order:)`.
///
/// "Have an invite code?" is for a partner who was sent a code. The code is
/// saved before sign-in, then joined on the next screen.
struct WelcomeView: View {
    let isWorking: Bool
    let signingInWith: AuthProvider?
    let pendingInviteCode: String?
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    let onSubmitInviteCode: (String) -> Void

    @State private var isInviteSheetPresented = false

    var body: some View {
        // The hero sits centered between the lockup and the buttons. When it
        // does not fit, such as at large text sizes, the same content scrolls
        // and the spacers shrink to their minimum.
        ViewThatFits(in: .vertical) {
            content

            ScrollView {
                content
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SignInView(
                isWorking: isWorking,
                signingInWith: signingInWith,
                pendingInviteCode: pendingInviteCode,
                onAppleSignIn: onAppleSignIn,
                onGoogleSignIn: onGoogleSignIn,
                onHaveInviteCode: { isInviteSheetPresented = true }
            )
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space12)
            .background(alignment: .top) {
                // Content scrolling under the buttons fades out instead of
                // being cut off by a hard edge.
                LinearGradient(
                    colors: [.paeoniaBackgroundPrimary.opacity(0), .paeoniaBackgroundPrimary],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.12)
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
            .launchEntrance(order: 2)
        }
        .background(PaeoniaGlowBackground())
        .sheet(isPresented: $isInviteSheetPresented) {
            PairingCodeEntrySheet(
                title: .welcomeInviteCodeTitle,
                message: .welcomeInviteCodeSubtitle,
                submitTitle: .welcomeInviteCodeContinue
            ) { code in
                onSubmitInviteCode(code)
                return true
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Same size and place as the lockup in `RootBrandedFrame`, so the
            // logo stays still while the screens after sign-in fade in under it.
            PaeoniaBrandLockup(wordmarkSize: 36, taglineSize: 17)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .launchEntrance(order: 0)

            Spacer(minLength: PaeoniaSpacing.space24)

            VStack(spacing: PaeoniaSpacing.space16) {
                WelcomeHero()

                Text(.welcomeSummary)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // Narrower than the column, so the two lines come out
                    // close in length under the picture.
                    .frame(maxWidth: 300)
            }
            .launchEntrance(order: 1)

            Spacer(minLength: PaeoniaSpacing.space24)
        }
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space24)
    }
}

#if DEBUG
#Preview {
    WelcomeView(
        isWorking: false,
        signingInWith: nil,
        pendingInviteCode: nil,
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onSubmitInviteCode: { _ in }
    )
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
