import SafariServices
import SwiftUI

/// The pre-auth sign-in screen. A private, plum-led entry point that shows the
/// Paeonia brand and offers the supported ways to get in: Apple and Google.
struct SignInView: View {
    let isWorking: Bool
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void

    private let contentMaxWidth: CGFloat = 430

    /// The legal page currently shown in the in-app browser, if any.
    @State private var activeLegalLink: LegalLink?

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
            PaeoniaBrandLockup(
                wordmarkSize: 28,
                taglineSize: 28,
                taglineColor: .paeoniaTextPrimary
            )

            PaeoniaHeartDivider()
        }
        .frame(maxWidth: .infinity)
    }

    private var promise: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
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
        Button(action: onAppleSignIn) {
            Label {
                Text(.authSignInAppleButton)
            } icon: {
                Image(systemName: "apple.logo")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(isWorking)
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
