import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The invite screen once its view model exists. `PairingInviteView` builds the view
/// model lazily and hands it over.
struct PairingInviteContent: View {
    let viewModel: PairingInviteViewModel
    let pendingJoinCode: String?
    let onClearPendingJoinCode: () -> Void
    let onInviteAccepted: () -> Void
    let onRefreshAccess: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var isConfirmingNewCode = false
    @State private var isEnteringCode = false
    @State private var isConfirmingJoin = false
    @State private var joinOrigin = JoinOrigin.entry

    private enum JoinOrigin {
        /// The code came from a link, so a saved copy exists that should go away when the
        /// user is done with it.
        case link
        case entry
    }

    private struct PendingJoinTaskID: Equatable {
        let code: String?
        let hasInvite: Bool
    }

    var body: some View {
        content
            .task {
                await viewModel.loadInviteIfNeeded()
            }
            // The link flow waits for the user's own code to show, so the confirmation
            // never appears over a loading screen.
            .task(id: PendingJoinTaskID(code: pendingJoinCode, hasInvite: viewModel.invite != nil)) {
                await previewPendingJoin()
            }
            .onChange(of: viewModel.error) { _, error in
                showBanner(for: error)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshOnForeground()
                }
            }
            .alert(
                Text(.pairingInviteNewCodeConfirmTitle),
                isPresented: $isConfirmingNewCode
            ) {
                Button(role: .destructive, action: replaceInviteCode) {
                    Text(.pairingInviteNewCodeButton)
                }

                Button(role: .cancel, action: {}) {
                    Text(.commonCancel)
                }
            } message: {
                Text(.pairingInviteNewCodeConfirmMessage)
            }
            .alert(
                Text(PaywallInviteConfirmation.title(for: viewModel.joinPreview)),
                isPresented: $isConfirmingJoin
            ) {
                Button(action: confirmJoin) {
                    Text(.paywallInviteConfirmAction)
                }

                Button(role: .cancel, action: cancelJoin) {
                    Text(.paywallInviteConfirmCancel)
                }
            } message: {
                Text(PaywallInviteConfirmation.message(for: viewModel.joinPreview))
            }
            .sheet(isPresented: $isEnteringCode, onDismiss: confirmJoinIfPreviewed) {
                PairingCodeEntrySheet(
                    title: .pairingCodeEntryTitle,
                    message: .pairingCodeEntryMessage,
                    submitTitle: .pairingCodeEntrySubmit
                ) { code in
                    joinOrigin = .entry
                    return await viewModel.previewJoin(codeInput: code)
                }
            }
    }

    // MARK: - Layout

    private var content: some View {
        ZStack {
            if !viewModel.isPresentationReady {
                // A quiet spinner under the logo, which stays in place from the
                // paywall. It fades out on top while the invite content (and its
                // code tiles' own entrance) starts underneath. A fade only, so
                // Reduce Motion needs no branch.
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(1)
            } else if let invite = viewModel.invite {
                readyContent(invite)
                    .transition(.opacity)
            } else {
                errorContent
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: contentPhase)
    }

    /// Which of the three surfaces (loading, invite, error) is showing, so the
    /// crossfade keys on the surface swap itself rather than on payload details.
    private var contentPhase: Int {
        if !viewModel.isPresentationReady {
            0
        } else if viewModel.invite != nil {
            1
        } else {
            2
        }
    }

    private func readyContent(_ invite: PairingInvite) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(.pairingInviteTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text(.pairingInviteMessage)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PairingInviteCodeBlock(invite: invite)

                PairingInviteWaitingLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, PaeoniaSpacing.space16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PairingInviteActionCluster(
                invite: invite,
                didCopyCode: viewModel.didCopyCode,
                isBusy: viewModel.isBusy,
                isJoining: viewModel.isJoining,
                onCopy: { copyInviteCode(invite.code) },
                onNewCode: { isConfirmingNewCode = true },
                onEnterCode: { isEnteringCode = true }
            )
        }
        .animation(PaeoniaMotion.stateChange, value: invite.id)
    }

    private var errorContent: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .pairingInviteErrorTitle,
                message: viewModel.error?.message ?? .pairingInviteErrorMessage,
                systemImage: "exclamationmark.icloud.fill"
            ) {
                Button {
                    Task {
                        await viewModel.createInvite()
                    }
                } label: {
                    Label {
                        Text(.pairingInviteRetryButton)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .disabled(viewModel.isLoading)
            }
        }
    }

    // MARK: - Actions

    private func showBanner(for error: PairingInviteFlowError?) {
        guard let error, error != .createFailed else {
            return
        }

        bannerCenter.show(.error(message: String(localized: error.message)))
        viewModel.clearError()
    }

    private func replaceInviteCode() {
        Task {
            if !(await viewModel.revokeAndCreateNewInvite()) {
                onRefreshAccess()
            }
        }
    }

    /// Re-checks access when the app comes back, in case the partner joined while it was
    /// away, and swaps in a new code if the old one ran out.
    private func refreshOnForeground() {
        onRefreshAccess()
        Task {
            if !(await viewModel.replaceInviteIfExpired()) {
                onRefreshAccess()
            }
        }
    }

    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(600),
            ]
        )
        PaeoniaHaptics.selection()
        AccessibilityNotification.Announcement(String(localized: .pairingInviteCopiedAnnouncement)).post()
        viewModel.noteCodeCopied()
    }

    // MARK: - Joining a partner's code

    private func previewPendingJoin() async {
        guard let pendingJoinCode, viewModel.invite != nil else {
            return
        }

        joinOrigin = .link
        if await viewModel.previewJoin(codeInput: pendingJoinCode) {
            isConfirmingJoin = true
        } else if viewModel.lastJoinError?.isFinalJoinFailure == true {
            onClearPendingJoinCode()
        }
    }

    /// Runs after the code sheet has closed. Showing the alert any earlier can lose it to
    /// the sheet's closing animation.
    private func confirmJoinIfPreviewed() {
        if viewModel.joinPreview != nil {
            isConfirmingJoin = true
        }
    }

    private func confirmJoin() {
        Task {
            if await viewModel.acceptPreviewedJoin() {
                onClearPendingJoinCode()
                onInviteAccepted()
            }
        }
    }

    private func cancelJoin() {
        viewModel.clearJoinPreview()
        if joinOrigin == .link {
            onClearPendingJoinCode()
        }
    }
}
