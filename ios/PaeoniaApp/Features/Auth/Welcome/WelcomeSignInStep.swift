import SafariServices
import SwiftUI
import UIKit

/// The last signed-out step: Continue with Apple or Google, under a headline that says
/// why this person is signing in (`WelcomeSignInMode`). A picture shows what they sign in
/// for: the first drawing they made, or the welcome peonies. Someone joining sees that
/// their invite code is saved and can change it. The privacy, terms and support
/// links sit under the buttons.
struct WelcomeSignInStep: View {
    let mode: WelcomeSignInMode
    let isWorking: Bool
    /// The provider whose sign-in is running. Only that button shows a spinner.
    let signingInWith: AuthProvider?
    let onBack: () -> Void
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    /// Saves a replacement invite code.
    let onSubmitInviteCode: (String) -> Void
    let onAppear: () -> Void
    /// The waiting first drawing as an image, for `.start(hasDrawing: true)`.
    let loadDrawing: () async -> UIImage?

    @State private var isInviteSheetPresented = false
    @State private var drawing: UIImage?
    @State private var hasLoadedDrawing = false

    var body: some View {
        // The picture and the headline sit together in the middle of the height under
        // Back, with the picture as large as fits. When the step does not fit, such as
        // at large text sizes, the content scrolls with the headline first and a smaller
        // picture under it.
        ViewThatFits(in: .vertical) {
            content(fillsHeight: true)

            ScrollView {
                content(fillsHeight: false)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .paeoniaBottomBar(spacing: 0) {
            VStack(spacing: PaeoniaSpacing.space12) {
                appleButton
                googleButton
                if mode == .joining {
                    inviteCodeSavedRow
                }
                WelcomeLegalLinks()
            }
            .padding(.top, PaeoniaSpacing.space12)
            .screenEntrance(order: 3)
            .onboardingBottomBarFade()
        }
        .onAppear(perform: onAppear)
        .task(id: mode) {
            guard mode == .start(hasDrawing: true), drawing == nil else {
                return
            }
            drawing = await loadDrawing()
            hasLoadedDrawing = true
        }
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

    /// `fillsHeight` puts the picture above the headline, grown into the free height up
    /// to its natural size. Otherwise the picture has a fixed height under the headline.
    private func content(fillsHeight: Bool) -> some View {
        VStack(spacing: 0) {
            WelcomeBackButton(action: onBack)
                .disabled(isWorking)
                .accessibilityIdentifier("welcome.signIn.back")
                .screenEntrance(order: 0)

            if fillsHeight {
                Spacer(minLength: PaeoniaSpacing.space24)

                VStack(spacing: PaeoniaSpacing.space32) {
                    picture
                        .frame(minHeight: 180)
                        .screenEntrance(order: 1, isReady: !isLoadingDrawing)

                    heading
                        .screenEntrance(order: 2)
                }
                // The picture takes the free height before the spacers do.
                .layoutPriority(1)

                Spacer(minLength: PaeoniaSpacing.space24)
            } else {
                VStack(spacing: PaeoniaSpacing.space32) {
                    heading
                        .screenEntrance(order: 1)

                    picture
                        .frame(height: 200)
                        .screenEntrance(order: 2, isReady: !isLoadingDrawing)
                }
                .padding(.top, PaeoniaSpacing.space24)
                .padding(.bottom, PaeoniaSpacing.space24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heading: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.signIn.title")

            Text(message)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var picture: some View {
        WelcomeSignInPicture(content: pictureContent)
    }

    private var isLoadingDrawing: Bool {
        mode == .start(hasDrawing: true) && !hasLoadedDrawing
    }

    /// The drawing when one waits and drew into an image, the peonies otherwise.
    private var pictureContent: WelcomeSignInPicture.Content {
        if isLoadingDrawing {
            return .loadingDrawing
        }
        if mode == .start(hasDrawing: true), let drawing {
            return .drawing(drawing)
        }
        return .hero
    }

    private var title: LocalizedStringResource {
        switch mode {
        case .start(hasDrawing: true): .welcomeSignInDrawingTitle
        case .start(hasDrawing: false): .welcomeSignInStartTitle
        case .joining: .welcomeSignInJoiningTitle
        case .returning: .welcomeSignInReturningTitle
        }
    }

    private var message: LocalizedStringResource {
        switch mode {
        case .start(hasDrawing: true): .welcomeSignInDrawingMessage
        case .start(hasDrawing: false): .welcomeSignInStartMessage
        case .joining: .welcomeSignInJoiningMessage
        case .returning: .welcomeSignInReturningMessage
        }
    }

    // MARK: Providers

    private var appleButton: some View {
        Button(action: onAppleSignIn) {
            Label {
                Text(.authSignInAppleButton)
            } icon: {
                Image(systemName: "apple.logo")
                    .accessibilityHidden(true)
            }
        }
        // Apple's sign-in button rules allow a custom button in black or white with the
        // Apple logo. White reads best on the plum background.
        .buttonStyle(AppleSignInButtonStyle(isLoading: signingInWith == .apple))
        .disabled(isWorking && signingInWith != .apple)
        .accessibilityIdentifier("auth.signIn.apple")
    }

    private var googleButton: some View {
        Button(action: onGoogleSignIn) {
            Label {
                Text(.authSignInGoogleButton)
            } icon: {
                Image(.googleG)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: signingInWith == .google))
        .disabled(isWorking && signingInWith != .google)
        .accessibilityIdentifier("auth.signIn.google")
    }

    // MARK: Invite code

    private var inviteCodeSavedRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space4) {
                inviteSavedLabel
                changeInviteCodeButton
            }

            VStack(spacing: 0) {
                inviteSavedLabel
                changeInviteCodeButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var inviteSavedLabel: some View {
        Label {
            Text(.welcomeInviteCodeSavedTitle)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextPrimary)
        .accessibilityIdentifier("welcome.signIn.inviteSaved")
    }

    private var changeInviteCodeButton: some View {
        Button {
            isInviteSheetPresented = true
        } label: {
            Text(.welcomeInviteCodeChange)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isWorking)
    }
}

/// The privacy, terms and support links, opened in an in-app browser.
private struct WelcomeLegalLinks: View {
    @State private var activeLink: LegalLink?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                link(.authSignInLegalPrivacy, .privacy)
                separator
                link(.authSignInLegalTerms, .terms)
                separator
                link(.authSignInSupport, .support)
            }

            VStack(spacing: 0) {
                link(.authSignInLegalPrivacy, .privacy)
                link(.authSignInLegalTerms, .terms)
                link(.authSignInSupport, .support)
            }
        }
        .font(PaeoniaTypography.caption)
        .sheet(item: $activeLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    private func link(_ title: LocalizedStringResource, _ link: LegalLink) -> some View {
        Button {
            activeLink = link
        } label: {
            Text(title)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.paeoniaTextSecondary)
        .accessibilityAddTraits(.isLink)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
    }
}

/// White "Continue with Apple" button with a black label, matching Apple's rules for
/// custom Sign in with Apple buttons. While loading it keeps its size, shows a spinner,
/// and ignores taps.
private struct AppleSignInButtonStyle: ButtonStyle {
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .foregroundStyle(.black)
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .background(.white.opacity(configuration.isPressed ? 0.85 : 1), in: shape)
            .opacity(isEnabled || isLoading ? 1 : 0.5)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !isLoading ? 0.98 : 1)
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
            .accessibilityValue(isLoading ? Text(.commonLoading) : Text(verbatim: ""))
    }
}

/// A legal page Paeonia can show in its in-app browser. `Identifiable` so it can drive a
/// `.sheet(item:)` presentation directly.
private enum LegalLink: String, Identifiable {
    case privacy
    case terms
    case support

    var id: String { rawValue }

    var url: URL {
        guard let url = URL(string: "https://paeonia.no/\(rawValue)") else {
            preconditionFailure("Invalid Paeonia legal URL path: \(rawValue)")
        }

        return url
    }
}

/// A thin SwiftUI wrapper around `SFSafariViewController` so legal pages open in an
/// in-app browser instead of leaving the app for Safari.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#if DEBUG
#Preview {
    PaeoniaScreenFrame {
        WelcomeSignInStep(
            mode: .start(hasDrawing: true),
            isWorking: false,
            signingInWith: nil,
            onBack: {},
            onAppleSignIn: {},
            onGoogleSignIn: {},
            onSubmitInviteCode: { _ in },
            onAppear: {},
            loadDrawing: { UIImage(resource: .placeholderSketch) }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
