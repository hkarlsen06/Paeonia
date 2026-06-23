import SwiftUI

/// The pre-auth sign-in screen. A private, plum-led entry point that shows the
/// Paeonia brand and offers the supported ways to get in: Apple, Google, and a
/// passkey for people who have signed in before, plus a way to sign up.
struct SignInView: View {
    let isWorking: Bool
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    let onPasskeySignIn: () -> Void
    let onSignUp: () -> Void

    private let contentMaxWidth: CGFloat = 430

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    logoLockup
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

    private var logoLockup: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Image(.paeoniaMark)
                .resizable()
                .scaledToFit()
                .frame(height: 52)
                .accessibilityHidden(true)

            Text(.appTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var promise: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Text(.appTagline)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.authStartMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space20) {
            VStack(spacing: PaeoniaSpacing.space12) {
                appleButton
                googleButton
            }

            accountLinks
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

    private var accountLinks: some View {
        HStack(spacing: 0) {
            accountLink(
                .authAccountPasskey,
                systemImage: "person.badge.key.fill",
                action: onPasskeySignIn
            )

            Rectangle()
                .fill(.paeoniaSurfacePressed)
                .frame(width: PaeoniaRadius.strokeDefault, height: 18)
                .accessibilityHidden(true)

            accountLink(.authAccountSignUp, action: onSignUp)
        }
        .frame(maxWidth: .infinity)
    }

    private func accountLink(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            linkLabel(title, systemImage: systemImage)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    @ViewBuilder
    private func linkLabel(
        _ title: LocalizedStringResource,
        systemImage: String?
    ) -> some View {
        if let systemImage {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
        } else {
            Text(title)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                legalLink(.authSignInLegalPrivacy, destination: LegalLinks.privacy)
                separator
                legalLink(.authSignInLegalTerms, destination: LegalLinks.terms)
                separator
                legalLink(.authSignInSupport, destination: LegalLinks.support)
            }

            VStack(spacing: PaeoniaSpacing.space4) {
                legalLink(.authSignInLegalPrivacy, destination: LegalLinks.privacy)
                legalLink(.authSignInLegalTerms, destination: LegalLinks.terms)
                legalLink(.authSignInSupport, destination: LegalLinks.support)
            }
        }
        .font(PaeoniaTypography.caption)
    }

    private func legalLink(
        _ title: LocalizedStringResource,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
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

private enum LegalLinks {
    static let privacy = url("privacy")
    static let terms = url("terms")
    static let support = url("support")

    private static func url(_ path: String) -> URL {
        guard let url = URL(string: "https://paeonia.no/\(path)") else {
            preconditionFailure("Invalid Paeonia legal URL path: \(path)")
        }

        return url
    }
}

#if DEBUG
#Preview("Sign in") {
    SignInView(
        isWorking: false,
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onPasskeySignIn: {},
        onSignUp: {}
    )
}
#endif
