import SwiftUI

/// The signed-out entry screen. One screen says what Paeonia does and lets the
/// person sign in right away; there is no carousel to page through first. It is
/// the first surface the cold-launch intro uncovers, so its parts cascade in
/// with `View.launchEntrance(order:)`.
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
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space32) {
                // Same size and place as the lockup in `RootBrandedFrame`, so the
                // logo stays still while the screens after sign-in fade in under it.
                PaeoniaBrandLockup(wordmarkSize: 36, taglineSize: 17)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .launchEntrance(order: 0)

                WelcomeFeatureList()
                    .launchEntrance(order: 1)
            }
            .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space24)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
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
}

/// What the two of you can do in Paeonia, one short row per feature.
private struct WelcomeFeatureList: View {
    private struct Feature: Identifiable {
        let systemImage: String
        let title: LocalizedStringResource
        let message: LocalizedStringResource

        var id: String { systemImage }
    }

    private let features = [
        Feature(
            systemImage: "scribble.variable",
            title: .welcomeFeatureDrawingTitle,
            message: .welcomeFeatureDrawingMessage
        ),
        Feature(
            systemImage: "bubble.left.and.bubble.right.fill",
            title: .welcomeFeatureQuestionsTitle,
            message: .welcomeFeatureQuestionsMessage
        ),
        Feature(
            systemImage: "photo.on.rectangle.angled",
            title: .welcomeFeatureMemoriesTitle,
            message: .welcomeFeatureMemoriesMessage
        ),
        Feature(
            systemImage: "calendar.badge.clock",
            title: .welcomeFeatureMilestonesTitle,
            message: .welcomeFeatureMilestonesMessage
        ),
    ]

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space20) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
                    Image(systemName: feature.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .frame(width: iconSize, height: iconSize)
                        .background(.paeoniaAccentPrimary.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                        Text(feature.title)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)

                        Text(feature.message)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
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
