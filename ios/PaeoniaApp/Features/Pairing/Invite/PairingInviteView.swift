import SwiftUI
import UIKit

struct PairingInviteView: View {
    @State private var viewModel: PairingInviteViewModel
    @State private var didCopyCode = false
    @State private var isCheckingPairing = false

    let onRefreshAccess: () -> Void

    init(
        session: AuthSession?,
        onRefreshAccess: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: PairingInviteViewModel(userID: session?.id))
        self.onRefreshAccess = onRefreshAccess
    }

    var body: some View {
        content
        .task {
            await viewModel.loadInviteIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.isPresentationReady {
            AuthLaunchingView()
        } else if let invite = viewModel.invite {
            readyContent(invite)
        } else {
            errorContent
        }
    }

    private func readyContent(_ invite: PairingInvite) -> some View {
        VStack(spacing: PaeoniaSpacing.space32) {
            Spacer(minLength: PaeoniaSpacing.space16)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space32) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(.pairingInviteTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.pairingInviteMessage)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                inviteCodeBlock(invite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: PaeoniaSpacing.space24)
            actionStack(invite)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
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

    private func inviteCodeBlock(_ invite: PairingInvite) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.pairingInviteCodeLabel)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)

            HStack(spacing: PaeoniaSpacing.space8) {
                ForEach(Array(invite.code.enumerated()), id: \.offset) { index, character in
                    PairingInviteCodeCharacterTile(
                        character: character,
                        inviteID: invite.id,
                        index: index
                    )
                    .id("\(invite.id)-\(index)")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.pairingInviteCodeLabel))
            .accessibilityValue(Text(invite.code))

            HStack(spacing: PaeoniaSpacing.space4) {
                Text(.pairingInviteExpiresLabel)
                Text(invite.expiresAt, format: .dateTime.month().day().hour().minute())
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
        }
    }

    private func actionStack(_ invite: PairingInvite) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            shareButton(for: invite)
            refreshButton
            secondaryActions(for: invite)
        }
    }

    private func shareButton(for invite: PairingInvite) -> some View {
        ShareLink(
            item: invite.joinURL,
            subject: Text(.pairingInviteShareSubject),
            message: Text(.pairingInviteShareMessage)
        ) {
            Label {
                Text(.pairingInviteShareButton)
            } icon: {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(viewModel.isLoading || viewModel.isRevoking)
    }

    private var refreshButton: some View {
        Button {
            checkPairing()
        } label: {
            Label {
                Text(isCheckingPairing ? .pairingInviteCheckingButton : .pairingInviteRefreshButton)
            } icon: {
                refreshButtonIcon
            }
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .disabled(isCheckingPairing || viewModel.isLoading || viewModel.isRevoking)
    }

    @ViewBuilder
    private var refreshButtonIcon: some View {
        if isCheckingPairing {
            ProgressView()
                .controlSize(.small)
                .tint(.paeoniaTextSecondary)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .accessibilityHidden(true)
        }
    }

    private func secondaryActions(for invite: PairingInvite) -> some View {
        HStack(spacing: 0) {
            copyActionButton(for: invite)
            footerDivider
            newCodeActionButton
        }
        .padding(.top, PaeoniaSpacing.space4)
    }

    private func copyActionButton(for invite: PairingInvite) -> some View {
        footerActionButton(
            title: didCopyCode ? .pairingInviteCopiedButton : .pairingInviteCopyButton,
            systemImage: didCopyCode ? "checkmark.circle.fill" : "doc.on.doc.fill",
            isDisabled: viewModel.isLoading || viewModel.isRevoking
        ) {
            copyInviteCode(invite.code)
        }
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(width: PaeoniaRadius.strokeHairline, height: 22)
            .accessibilityHidden(true)
    }

    private var newCodeActionButton: some View {
        footerActionButton(
            title: .pairingInviteNewCodeButton,
            systemImage: "arrow.clockwise",
            isDisabled: viewModel.isLoading || viewModel.isRevoking
        ) {
            replaceInviteCode()
        }
    }

    private func replaceInviteCode() {
        Task {
            let createdNewInvite = await viewModel.revokeAndCreateNewInvite()
            if !createdNewInvite {
                checkPairing()
            }
        }
    }

    private func footerActionButton(
        title: LocalizedStringResource,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.button)
            .foregroundStyle(isDisabled ? .paeoniaTextTertiary : .paeoniaTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        didCopyCode = true

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                didCopyCode = false
            }
        }
    }

    private func checkPairing() {
        guard !isCheckingPairing else {
            return
        }

        withAnimation(PaeoniaMotion.stateChange) {
            isCheckingPairing = true
        }
        onRefreshAccess()

        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                withAnimation(PaeoniaMotion.stateChange) {
                    isCheckingPairing = false
                }
            }
        }
    }
}

private struct PairingInviteCodeCharacterTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var inviteCodeTileHeight: CGFloat = 58
    @State private var isSettled = false

    let character: Character
    let inviteID: UUID
    let index: Int

    var body: some View {
        Text(String(character))
            .font(.system(.title2, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: inviteCodeTileHeight)
            .background(.paeoniaBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .scaleEffect(isSettled ? 1 : 0.72)
            .offset(y: isSettled ? 0 : 12)
            .opacity(isSettled ? 1 : 0)
            .onAppear(perform: bounceIntoPlace)
            .onChange(of: inviteID) { _, _ in
                isSettled = false
                bounceIntoPlace()
            }
    }

    private func bounceIntoPlace() {
        guard !reduceMotion else {
            isSettled = true
            return
        }

        withAnimation(
            .spring(response: 0.42, dampingFraction: 0.58)
            .delay(Double(index) * 0.035)
        ) {
            isSettled = true
        }
    }
}

#Preview {
    PairingInviteView(
        session: AuthSession(
            id: UUID().uuidString,
            provider: .apple,
            displayName: "Alvilde",
            timeZoneID: "Europe/Oslo",
            profilePhotoAssetID: nil,
            profileStatus: .complete
        ),
        onRefreshAccess: {}
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
