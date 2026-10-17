import SwiftUI

/// The screen for someone who has a partner's code. The root shows it instead of
/// the paywall or the invite screen while a code is saved. It shows who the code
/// belongs to and joins them. Without a code the person goes back to the screen
/// this one stood in for.
struct PairingJoinView: View {
    let viewModel: PairingJoinViewModel
    /// The saved partner code. Nil only for a moment while the screen leaves.
    let code: String?
    let currentUserID: String?
    /// The joiner has no subscription of their own, so this screen stands in for
    /// the paywall. It says the partner's subscription covers them and keeps the
    /// paywall's sign out and delete account links.
    let replacesPaywall: Bool
    /// Checks a code typed in the code sheet and, if it works, saves it as the
    /// partner code. Returns false to keep the sheet open.
    let onSubmitCode: (String) async -> Bool
    let onAccepted: () -> Void
    /// Forgets the saved code.
    let onForgetCode: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// The preview on screen. It only ever moves to a newer preview, so the content
    /// stays put while the app moves on after a join.
    @State private var shownPreview: PairingInvitePreview?
    @State private var isEnteringCode = false
    @State private var isConfirmingDelete = false
    /// The join went through. The button keeps its spinner until the next screen
    /// arrives.
    @State private var didJoin = false

    var body: some View {
        ZStack {
            ScrollView {
                PairingJoinInviterContent(preview: shownPreview, showsCoverage: replacesPaywall)
                    .padding(.top, PaeoniaSpacing.space16)
                    .padding(.bottom, PaeoniaSpacing.space24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if shownPreview == nil {
                loadingOrFailure
                    .transition(.opacity)
            }
        }
        // A fade only, so Reduce Motion needs no branch.
        .animation(PaeoniaMotion.meaningfulMoment, value: shownPreview == nil)
        .animation(PaeoniaMotion.stateChange, value: viewModel.checkFailure)
        .paeoniaBottomBar(spacing: 0) {
            actions
                .padding(.top, PaeoniaSpacing.space12)
                .onboardingBottomBarFade()
                .screenEntrance(order: 4)
        }
        .task(id: code) {
            // A different code, from a new link, must not keep showing who the
            // last one belonged to.
            if code != nil, viewModel.preview(for: code) == nil {
                shownPreview = nil
            }
            await checkCode()
        }
        .onChange(of: viewModel.preview(for: code), initial: true) { _, preview in
            if let preview {
                shownPreview = preview
            }
        }
        .sheet(isPresented: $isEnteringCode) {
            PairingCodeEntrySheet(
                title: .pairingCodeEntryTitle,
                message: .pairingCodeEntryMessage,
                submitTitle: .pairingCodeEntrySubmit,
                onSubmit: { await onSubmitCode($0) }
            )
        }
        .alert(Text(.authDeleteAccountConfirmTitle), isPresented: $isConfirmingDelete) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }
            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
        }
    }

    // MARK: - Layout

    /// A quiet spinner while the code is checked, or a retry when the check could
    /// not finish. The bottom buttons stay, so the person can always use another
    /// code or go back.
    @ViewBuilder
    private var loadingOrFailure: some View {
        if let failure = viewModel.checkFailure, !viewModel.isChecking {
            PaeoniaLoadFailureView(
                failure: failure,
                offlineMessage: .pairingJoinErrorCheckFailed,
                failedMessage: .pairingJoinErrorCheckFailedLater
            ) {
                Button {
                    Task { await checkCode() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Button(action: join) {
                Text(PairingJoinCopy.title(for: shownPreview))
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isAccepting || didJoin))
            .disabled(viewModel.preview(for: code) == nil || viewModel.isChecking)
            .accessibilityIdentifier("pairing.join.accept")

            quietButton(.pairingJoinOtherCode) {
                isEnteringCode = true
            }

            quietButton(.pairingJoinNoCode, action: onForgetCode)

            if replacesPaywall {
                accountActions
            }
        }
        .disabled(viewModel.isAccepting || didJoin)
    }

    private func quietButton(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
    }

    /// The same quiet links the paywall and profile setup have.
    private var accountActions: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button(action: onSignOut) {
                accountActionLabel(.authSignOutButton)
            }

            Text(verbatim: "·")
                .accessibilityHidden(true)

            Button {
                isConfirmingDelete = true
            } label: {
                accountActionLabel(.authDeleteAccountButton)
            }
        }
        .buttonStyle(.plain)
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextTertiary)
    }

    private func accountActionLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
    }

    // MARK: - Actions

    /// A code that cannot work anymore is forgotten, which takes the person back to
    /// the paywall or the invite screen. The banner says why.
    private func checkCode() async {
        guard let code,
              !(await viewModel.checkCode(code, currentUserID: currentUserID)),
              let error = viewModel.lastError,
              error.isFinal
        else {
            return
        }

        bannerCenter.show(.error(message: String(localized: error.message)))
        onForgetCode()
    }

    private func join() {
        guard !viewModel.isBusy, !didJoin else {
            return
        }

        PaeoniaHaptics.partnerJoinSent()
        Task {
            if await viewModel.acceptCheckedCode(code) {
                bannerCenter.dismiss()
                // The root forgets the code once the paired screen is in place.
                // Forgetting it here would show the previous screen for a moment.
                didJoin = true
                onAccepted()
            } else if let error = viewModel.lastError {
                bannerCenter.show(.error(message: String(localized: error.message)))
                if error.isFinal {
                    onForgetCode()
                }
            }
        }
    }
}
