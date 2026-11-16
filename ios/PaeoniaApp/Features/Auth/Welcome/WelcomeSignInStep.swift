import AuthenticationServices
import SafariServices
import SwiftUI
import UIKit

/// The last signed-out step: Continue with Apple, Google or email, under a headline that says
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
    /// Emails a sign-in code. Returns nil once it is on its way.
    let onSendEmailCode: (String) async -> EmailSignInError?
    /// Signs in with the emailed code. Returns nil once signed in.
    let onVerifyEmailCode: (String) async -> EmailSignInError?
    /// Saves a replacement invite code.
    let onSubmitInviteCode: (String) -> Void
    let onAppear: () -> Void
    /// The waiting first drawing as an image, for `.start(hasDrawing: true)`.
    let loadDrawing: () async -> UIImage?

    @State private var isInviteSheetPresented = false
    @State private var isEmailSheetPresented = false
    @State private var drawing: UIImage?
    @State private var hasLoadedDrawing = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 0) {
                        content(fillsHeight: false)
                        signInActions.paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                regularContent
                    .paeoniaBottomBar(spacing: 0) { signInActions }
            }
        }
        .closesOnSwipeRight(isEnabled: !isWorking, perform: onBack)
        .onAppear(perform: onAppear)
        .task(id: mode) {
            guard mode == .start(hasDrawing: true), drawing == nil else { return }
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
        .sheet(isPresented: $isEmailSheetPresented) {
            EmailSignInSheet(onSendCode: onSendEmailCode, onVerifyCode: onVerifyEmailCode)
        }
    }

    private var regularContent: some View {
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
    }

    private var signInActions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            appleButton
            googleButton
            emailButton
            if mode == .joining {
                inviteCodeSavedRow
            }
            WelcomeLegalLinks()
        }
        .padding(.top, PaeoniaSpacing.space12)
        .screenEntrance(order: 3)
        .onboardingBottomBarFade()
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
        AppleSignInButton(action: onAppleSignIn)
            .frame(height: PaeoniaSpacing.buttonHeight)
            .overlay {
                if signingInWith == .apple {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                        .fill(.white)
                        .overlay {
                            ProgressView()
                                .tint(.black)
                        }
                        .accessibilityLabel(Text(.commonLoading))
                }
            }
            .disabled(isWorking)
    }

    private var googleButton: some View {
        Button(action: onGoogleSignIn) {
            // Logo beside the centered title, like Apple's button above.
            HStack(spacing: PaeoniaSpacing.space8) {
                Image(.googleG)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(.authSignInGoogleButton)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(WelcomeSignInButtonStyle(isLoading: signingInWith == .google))
        .disabled(isWorking && signingInWith != .google)
        .accessibilityIdentifier("auth.signIn.google")
    }

    private var emailButton: some View {
        Button {
            isEmailSheetPresented = true
        } label: {
            HStack(spacing: PaeoniaSpacing.space8) {
                Image(systemName: "envelope")
                    .accessibilityHidden(true)
                Text(.authSignInEmailButton)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(WelcomeSignInButtonStyle(isLoading: signingInWith == .email))
        .disabled(isWorking && signingInWith != .email)
        .accessibilityIdentifier("auth.signIn.email")
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

/// The Google and email buttons. The label stays in place under the spinner during sign-in.
private struct WelcomeSignInButtonStyle: ButtonStyle {
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .foregroundStyle(.paeoniaTextPrimary)
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(.paeoniaTextPrimary)
                        .accessibilityHidden(true)
                }
            }
            .background(Color.paeoniaSurfacePrimary, in: shape)
            .overlay {
                shape.strokeBorder(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .opacity(isEnabled || isLoading ? 1 : 0.5)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !isLoading && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
            .accessibilityValue(isLoading ? Text(.commonLoading) : Text(verbatim: ""))
    }
}

/// Apple's own Sign in with Apple button. Apple allows a custom button only with the
/// logo artwork from Apple Design Resources, and App Review checks custom buttons, so
/// the system button is the safe choice. It translates its title itself.
private struct AppleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .white)
        button.cornerRadius = PaeoniaRadius.radius16
        button.accessibilityIdentifier = "auth.signIn.apple"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
        button.alpha = context.environment.isEnabled ? 1 : 0.5
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
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
            onSendEmailCode: { _ in nil },
            onVerifyEmailCode: { _ in nil },
            onSubmitInviteCode: { _ in },
            onAppear: {},
            loadDrawing: { UIImage(resource: .placeholderSketch) }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
