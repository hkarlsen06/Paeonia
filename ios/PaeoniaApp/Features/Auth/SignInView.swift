import SafariServices
import SwiftUI
import UIKit

/// The sign-in controls at the bottom of the welcome screen: Apple and Google,
/// the partner invite code row, and the privacy, terms, and support links.
struct SignInView: View {
    let isWorking: Bool
    /// The provider whose sign-in is running. Only that button shows a spinner.
    let signingInWith: AuthProvider?
    let pendingInviteCode: String?
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    /// Enters or replaces a partner invite code. A saved code gets an explicit
    /// state so the user knows it will be used after sign-in.
    let onHaveInviteCode: () -> Void
    /// Saves the code from a pasted invite link.
    let onPasteInviteCode: (String) -> Void

    @Environment(\.scenePhase) private var scenePhase

    /// The legal page currently shown in the in-app browser, if any.
    @State private var activeLegalLink: LegalLink?
    /// Whether the clipboard holds something that looks like a link. The `/join`
    /// web page copies the invite link when a partner without the app taps
    /// "Install", because the link itself is lost on the way through the App
    /// Store. Checking the pattern does not read the clipboard, so iOS shows no
    /// paste prompt. Only the system paste button reads it.
    @State private var clipboardHasLink = false

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            appleButton
            googleButton
            inviteCodeRow
            footer
        }
        .sheet(item: $activeLegalLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        // Checked again on return to the app, since the link may be copied after
        // the welcome screen first appeared.
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }
            let patterns = try? await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL])
            clipboardHasLink = patterns?.contains(\.probableWebURL) ?? false
        }
    }

    // MARK: - Providers

    private var appleButton: some View {
        Button(action: onAppleSignIn) {
            Label {
                Text(.authSignInAppleButton)
            } icon: {
                Image(systemName: "apple.logo")
                    .accessibilityHidden(true)
            }
        }
        // Apple's sign-in button rules allow a custom button in black or white
        // with the Apple logo. White reads best on the plum background.
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

    // MARK: - Invite code

    @ViewBuilder
    private var inviteCodeRow: some View {
        if pendingInviteCode != nil {
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
        } else if clipboardHasLink {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    invitePastePrompt
                    invitePasteButton
                }

                VStack(spacing: PaeoniaSpacing.space8) {
                    invitePastePrompt
                    invitePasteButton
                }
            }
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
        } else {
            Button(action: onHaveInviteCode) {
                Text(.welcomeHaveInviteCode)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("auth.welcome.inviteCode")
        }
    }

    private var invitePastePrompt: some View {
        Text(.welcomeInvitePastePrompt)
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.center)
    }

    /// The system paste button reads the clipboard without a permission prompt.
    /// Anything other than a Paeonia join link opens the code sheet, so the
    /// partner can still type the code.
    private var invitePasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            if let code = PairingInviteCode.joinLinkCode(in: strings.joined(separator: " ")) {
                onPasteInviteCode(code)
            } else {
                onHaveInviteCode()
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(.paeoniaAccentSecondary)
        .disabled(isWorking)
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
    }

    private var changeInviteCodeButton: some View {
        Button(action: onHaveInviteCode) {
            Text(.welcomeInviteCodeChange)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
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

            VStack(spacing: 0) {
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

/// White "Continue with Apple" button with a black label, matching Apple's
/// rules for custom Sign in with Apple buttons. While loading it keeps its
/// size, shows a spinner, and ignores taps.
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
