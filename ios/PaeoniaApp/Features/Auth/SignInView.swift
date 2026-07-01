import SafariServices
import SwiftUI

/// The pre-auth sign-in screen. A private, plum-led entry point that shows the
/// Paeonia brand and offers the supported ways to get in: Apple and Google.
struct SignInView: View {
    let isWorking: Bool
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void

    private let contentMaxWidth: CGFloat = 430
    @ScaledMetric(relativeTo: .largeTitle) private var brandMarkHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) private var brandWordmarkSize: CGFloat = 28

    /// The legal page currently shown in the in-app browser, if any.
    @State private var activeLegalLink: LegalLink?

    /// Which provider the user tapped, so its button can show a spinner while the
    /// sign-in finishes. After the provider's own consent sheet dismisses there is
    /// still a token exchange to complete; without this the screen looks frozen.
    @State private var pendingProvider: AuthSignInProvider?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    brandLockup
                        .padding(.top, PaeoniaSpacing.space40)

                    Spacer(minLength: PaeoniaSpacing.space24)

                    promise

                    Spacer(minLength: PaeoniaSpacing.space24)

                    VStack(spacing: PaeoniaSpacing.space32) {
                        actions
                        footer
                    }
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.bottom, PaeoniaSpacing.space16)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(background)
        .preferredColorScheme(.dark)
        .sheet(item: $activeLegalLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        // Once the flow settles (success leaves this screen; failure or cancel
        // returns control here), drop the spinner so the buttons are tappable
        // again for a retry.
        .onChange(of: isWorking) { _, isWorking in
            if !isWorking {
                pendingProvider = nil
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary

            // A soft petal glow as ambient light. Static, so it is comfortable
            // with Reduce Motion and never competes with the content.
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.16), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Brand

    private var brandLockup: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Image(.paeoniaMark)
                .resizable()
                .scaledToFit()
                .frame(height: brandMarkHeight)
                .accessibilityHidden(true)

            Text(.appTitle)
                .font(PaeoniaTypography.wordmark(size: brandWordmarkSize))
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var promise: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Text(.appTagline)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)

            PaeoniaHeartDivider()

            Text(.authStartMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            appleButton
            googleButton
        }
    }

    private var appleButton: some View {
        Button {
            pendingProvider = .apple
            onAppleSignIn()
        } label: {
            Label {
                Text(.authSignInAppleButton)
            } icon: {
                if pendingProvider == .apple {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                } else {
                    Image(systemName: "apple.logo")
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(isWorking)
    }

    private var googleButton: some View {
        Button {
            pendingProvider = .google
            onGoogleSignIn()
        } label: {
            Label {
                Text(.authSignInGoogleButton)
            } icon: {
                if pendingProvider == .google {
                    ProgressView()
                        .tint(.paeoniaTextPrimary)
                } else {
                    Image(.googleG)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .disabled(isWorking)
    }

    // MARK: - Footer

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                legalLink(.authSignInLegalPrivacy, link: .privacy)
                separator
                legalLink(.authSignInLegalTerms, link: .terms)
                separator
                legalLink(.authSignInSupport, link: .support)
            }

            VStack(spacing: PaeoniaSpacing.space4) {
                legalLink(.authSignInLegalPrivacy, link: .privacy)
                legalLink(.authSignInLegalTerms, link: .terms)
                legalLink(.authSignInSupport, link: .support)
            }
        }
        .font(PaeoniaTypography.caption)
    }

    private func legalLink(
        _ title: LocalizedStringResource,
        link: LegalLink
    ) -> some View {
        Button {
            activeLegalLink = link
        } label: {
            Text(title)
                .frame(minHeight: 44)
        }
        .foregroundStyle(.paeoniaTextSecondary)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
    }
}

/// The sign-in provider whose button is currently mid-flight, used only to show
/// a per-button spinner.
private enum AuthSignInProvider {
    case apple
    case google
}

/// A legal page Paeonia can show in its in-app browser. `Identifiable` so it can
/// drive a `.sheet(item:)` presentation directly.
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

/// A thin SwiftUI wrapper around `SFSafariViewController` so legal pages open in
/// an in-app browser instead of leaving the app for Safari.
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
#Preview("Sign in") {
    SignInView(
        isWorking: false,
        onAppleSignIn: {},
        onGoogleSignIn: {}
    )
}

#endif
