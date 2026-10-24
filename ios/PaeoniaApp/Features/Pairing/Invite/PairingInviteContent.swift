import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The invite screen once its view model exists. `PairingInviteView` builds the view
/// model lazily and hands it over.
struct PairingInviteContent: View {
    let viewModel: PairingInviteViewModel
    /// The first question. Nil until the parent builds it.
    let firstDay: InviterFirstDayModel?
    /// Adds the button that opens Apple's subscription sheet, below the first screen.
    let showsManageSubscription: Bool
    let onSubmitJoinCode: (String) async -> Bool
    let onRefreshAccess: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var isConfirmingNewCode = false
    @State private var isEnteringCode = false
    /// The scroll view's height above the action buttons.
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        content
            .task {
                await viewModel.loadInviteIfNeeded()
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
            .sheet(isPresented: $isEnteringCode) {
                PairingCodeEntrySheet(
                    title: .pairingCodeEntryTitle,
                    message: .pairingCodeEntryMessage,
                    submitTitle: .pairingCodeEntrySubmit,
                    onSubmit: { await onSubmitJoinCode($0) }
                )
            }
    }

    // MARK: - Layout

    private var content: some View {
        ZStack {
            if !viewModel.isPresentationReady {
                // A quiet spinner. It fades out on top while the invite content
                // (and its code tiles' own entrance) starts underneath. A fade
                // only, so Reduce Motion needs no branch.
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
        PaeoniaScreenScroll {
            VStack(spacing: 0) {
                if showsManageSubscription {
                    // The invite fills the first screen, so the subscription button
                    // only shows once someone scrolls to it.
                    inviteDetails(invite)
                        .frame(minHeight: max(visibleHeight - 2 * PaeoniaSpacing.space24, 0))

                    PairingInviteManageSubscriptionButton()
                        .padding(.top, PaeoniaSpacing.space24)
                } else {
                    inviteDetails(invite)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, height in
            visibleHeight = height
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PairingInviteActionCluster(
                invite: invite,
                shareMessage: firstDay?.shareMessage ?? .pairingInviteShareMessage,
                didCopyCode: viewModel.didCopyCode,
                isBusy: viewModel.isBusy,
                onCopy: { copyInviteCode(invite.code) },
                onNewCode: { isConfirmingNewCode = true },
                onEnterCode: { isEnteringCode = true }
            )
        }
        .animation(PaeoniaMotion.stateChange, value: invite.id)
    }

    private func inviteDetails(_ invite: PairingInvite) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
            header

            PairingInviteCodeBlock(invite: invite)

            PairingInviteWaitingLine(notifiesOnJoin: firstDay?.notificationsAllowed == true)

            if let firstDay {
                InviterQuestionsRow(model: firstDay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
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
    }

    private var errorContent: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .pairingInviteErrorTitle,
                message: viewModel.error?.message(viewModel.errorFailure) ?? .commonActionFailedMessage,
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

        bannerCenter.show(.error(message: String(localized: error.message(viewModel.errorFailure))))
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
}
