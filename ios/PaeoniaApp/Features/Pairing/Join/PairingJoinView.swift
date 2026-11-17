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
    /// Which of the two restore buttons shows the spinner.
    @State private var restoreChosen = false
    /// `isWaitingForPartner` as shown, changed inside an animation.
    @State private var showsWaiting = false

    var body: some View {
        ZStack {
            PaeoniaScreenScroll {
                // Waiting for the inviter is a new step, so the screen fades to it whole
                // instead of reflowing text in place.
                PairingJoinInviterContent(
                    preview: shownPreview,
                    showsCoverage: replacesPaywall,
                    isWaitingForPartner: showsWaiting
                )
                .id(showsWaiting)
                .transition(.opacity)
            }

            if shownPreview == nil {
                loadingOrFailure
                    .transition(.opacity)
            }
        }
        // A fade only, so Reduce Motion needs no branch.
        .animation(PaeoniaMotion.meaningfulMoment, value: shownPreview == nil)
        .animation(PaeoniaMotion.stateChange, value: viewModel.checkFailure)
        // In one animated transaction, so the bottom bar's height changes with the fade.
        .onChange(of: viewModel.isWaitingForPartner, initial: true) { _, waiting in
            withAnimation(PaeoniaMotion.stateChange) {
                showsWaiting = waiting
            }
        }
        .paeoniaBottomBar(spacing: 0) {
            actions
                .id(showsWaiting)
                .transition(.opacity)
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
            joinButtons

            if !showsWaiting {
                quietButton(.pairingJoinOtherCode) {
                    isEnteringCode = true
                }

                quietButton(.pairingJoinNoCode, action: onForgetCode)
            }

            if replacesPaywall {
                accountActions
            }
        }
        .disabled(viewModel.isAccepting || didJoin)
    }

    /// One Join button, or the two restore choices when the two can bring back what
    /// they had, or only "Start fresh instead" while the inviter decides.
    @ViewBuilder
    private var joinButtons: some View {
        let isFreshLoading = (viewModel.isAccepting && !restoreChosen) || didJoin
        if showsWaiting {
            joinButton(.pairingRestoreWaitingStartFresh, restore: false, id: "pairing.join.restore.startFreshInstead")
                .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: isFreshLoading))
        } else if shownPreview?.canRestore == true {
            joinButton(.pairingRestoreBringBack, restore: true, id: "pairing.join.restore.bringBack")
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isAccepting && restoreChosen))
                .disabled(!canJoin)
            joinButton(.pairingRestoreStartFresh, restore: false, id: "pairing.join.restore.startFresh")
                .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: isFreshLoading))
                .disabled(!canJoin)
        } else {
            joinButton(PairingJoinCopy.title(for: shownPreview), restore: false, id: "pairing.join.accept")
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isAccepting || didJoin))
                .disabled(!canJoin)
        }
    }

    private func joinButton(_ title: LocalizedStringResource, restore: Bool, id: String) -> some View {
        Button {
            join(restore: restore)
        } label: {
            Text(title)
        }
        .accessibilityIdentifier(id)
    }

    private var canJoin: Bool {
        viewModel.preview(for: code) != nil && !viewModel.isChecking
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

    /// With `restore`, asks the inviter to bring back what the two had. The screen then
    /// waits for their answer, and either answer pairs the two.
    private func join(restore: Bool) {
        guard !viewModel.isBusy, !didJoin else {
            return
        }

        restoreChosen = restore
        PaeoniaHaptics.partnerJoinSent()
        Task {
            if await viewModel.acceptCheckedCode(code, restore: restore) {
                bannerCenter.dismiss()
                guard !viewModel.isWaitingForPartner else {
                    return
                }
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
