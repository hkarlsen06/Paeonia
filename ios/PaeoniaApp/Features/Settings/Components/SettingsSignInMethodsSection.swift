import SwiftUI

/// The profile screen's sign-in methods: Apple and Google, linked or not.
///
/// A linked method shows a checkmark, and tapping it asks before unlinking, but
/// only while another method stays linked. An unlinked one has a Link row, which
/// opens Apple's sheet or Google's web sheet. Both end up on this one account.
struct SettingsSignInMethodsSection: View {
    let viewModel: SignInMethodsViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @State private var methodToUnlink: SignInMethod?

    var body: some View {
        Section {
            ForEach(SignInMethod.allCases) { method in
                if let linked = viewModel.linkedMethods.first(where: { $0.method == method }) {
                    linkedRow(linked)
                } else {
                    linkRow(method)
                }
            }
        } header: {
            Text(.settingsSignInMethodsTitle)
        } footer: {
            footer
        }
    }

    @ViewBuilder
    private func linkedRow(_ linked: LinkedSignInMethod) -> some View {
        let method = linked.method
        if viewModel.canUnlink {
            Button {
                methodToUnlink = method
            } label: {
                linkedContent(linked)
            }
            .disabled(viewModel.isBusy)
            .accessibilityValue(Text(.settingsSignInMethodsLinkedLabel))
            .accessibilityIdentifier("settings.signInMethods.\(method.rawValue).linked")
            .alert(
                Text(.settingsSignInMethodsUnlinkConfirmTitle(method.brandName)),
                isPresented: Binding(
                    get: { methodToUnlink == method },
                    set: { if !$0, methodToUnlink == method { methodToUnlink = nil } }
                )
            ) {
                Button(role: .destructive) {
                    unlink(method)
                } label: {
                    Text(.settingsSignInMethodsUnlinkConfirmAction)
                }
                Button(role: .cancel, action: {}) {
                    Text(.commonCancel)
                }
            } message: {
                Text(.settingsSignInMethodsUnlinkConfirmMessage(method.brandName))
            }
        } else {
            // The only method left. It cannot be unlinked, so it is not a button.
            linkedContent(linked)
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(.settingsSignInMethodsLinkedLabel))
                .accessibilityIdentifier("settings.signInMethods.\(method.rawValue).linked")
        }
    }

    private func linkedContent(_ linked: LinkedSignInMethod) -> some View {
        let method = linked.method
        return HStack {
            Label {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(verbatim: method.brandName)
                        .foregroundStyle(.paeoniaTextPrimary)
                    if let email = linked.email {
                        Text(verbatim: email)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } icon: {
                method.icon
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.busyMethod == method {
                ProgressView()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func linkRow(_ method: SignInMethod) -> some View {
        Button {
            link(method)
        } label: {
            HStack {
                Label {
                    Text(.settingsSignInMethodsLink(method.brandName))
                        .foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    method.icon
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.busyMethod == method {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(viewModel.isBusy)
        .accessibilityIdentifier("settings.signInMethods.\(method.rawValue).link")
    }

    @ViewBuilder
    private var footer: some View {
        if let missing = viewModel.unlinkedMethods.first {
            Text(.settingsSignInMethodsFooterOne(missing.brandName))
        } else {
            Text(.settingsSignInMethodsFooterBoth)
        }
    }

    private func link(_ method: SignInMethod) {
        Task {
            await viewModel.link(method)
            showNotice()
        }
    }

    private func unlink(_ method: SignInMethod) {
        Task {
            await viewModel.unlink(method)
            showNotice()
        }
    }

    private func showNotice() {
        guard let notice = viewModel.notice else {
            return
        }
        viewModel.consumeNotice()
        bannerCenter.show(notice.banner)
    }
}

private extension SignInMethod {
    /// Brand names stay unlocalized; only the sentence around them is translated.
    var brandName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }

    @ViewBuilder
    var icon: some View {
        switch self {
        case .apple:
            Image(systemName: "apple.logo")
        case .google:
            Image(.googleG)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }
}

private extension SignInMethodsViewModel.Notice {
    var banner: PaeoniaBannerContent {
        switch self {
        case let .linked(method):
            .info(
                title: String(localized: .settingsSignInMethodsLinkedTitle(method.brandName)),
                message: String(localized: .settingsSignInMethodsLinkedMessage)
            )
        case let .unlinked(method):
            .info(
                title: String(localized: .settingsSignInMethodsUnlinkedTitle(method.brandName)),
                message: String(localized: .settingsSignInMethodsUnlinkedMessage)
            )
        case let .linkFailed(problem, method):
            .error(
                title: problem == .offline
                    ? String(localized: .commonOfflineTitle)
                    : String(localized: .settingsSignInMethodsLinkFailedTitle(method.brandName)),
                message: message(for: problem, method: method)
            )
        case let .unlinkFailed(problem, method):
            .error(
                title: problem == .offline
                    ? String(localized: .commonOfflineTitle)
                    : String(localized: .settingsSignInMethodsUnlinkFailedTitle(method.brandName)),
                message: message(for: problem, method: method)
            )
        }
    }

    private func message(for problem: SignInMethodsViewModel.Problem, method: SignInMethod) -> String {
        switch problem {
        case .usedByAnotherAccount:
            String(localized: .settingsSignInMethodsUsedElsewhereMessage(method.brandName))
        case .needsFreshSignIn:
            String(localized: .settingsSignInMethodsFreshSignInMessage)
        case .offline:
            String(localized: .settingsSignInMethodsOfflineMessage)
        case .other:
            String(localized: .commonActionFailedMessage)
        }
    }
}
