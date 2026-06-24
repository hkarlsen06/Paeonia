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
        if let invite = viewModel.invite {
            readyContent(invite)
        } else if viewModel.isLoading || viewModel.error == nil {
            loadingContent
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

    private var loadingContent: some View {
        PaeoniaCard {
            VStack(spacing: PaeoniaSpacing.space16) {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)

                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(.pairingInviteLoadingTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.pairingInviteLoadingMessage)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaeoniaSpacing.space8)
        }
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

            Button {
                checkPairing()
            } label: {
                Label {
                    Text(isCheckingPairing ? .pairingInviteCheckingButton : .pairingInviteRefreshButton)
                } icon: {
                    if isCheckingPairing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.paeoniaTextSecondary)
                    } else {
                        Image(systemName: "questionmark.circle.fill")
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(isCheckingPairing || viewModel.isLoading || viewModel.isRevoking)

            HStack(spacing: 0) {
                footerActionButton(
                    title: didCopyCode ? .pairingInviteCopiedButton : .pairingInviteCopyButton,
                    systemImage: didCopyCode ? "checkmark.circle.fill" : "doc.on.doc.fill",
                    isDisabled: viewModel.isLoading || viewModel.isRevoking
                ) {
                    copyInviteCode(invite.code)
                }

                Rectangle()
                    .fill(.paeoniaSurfacePressed)
                    .frame(width: PaeoniaRadius.strokeHairline, height: 22)
                    .accessibilityHidden(true)

                footerActionButton(
                    title: .pairingInviteNewCodeButton,
                    systemImage: "arrow.clockwise",
                    isDisabled: viewModel.isLoading || viewModel.isRevoking
                ) {
                    Task {
                        await viewModel.revokeAndCreateNewInvite()
                    }
                }
            }
            .padding(.top, PaeoniaSpacing.space4)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            } icon: {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.button)
            .foregroundStyle(isDisabled ? .paeoniaTextTertiary : .paeoniaTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
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
    @State private var isSettled = false

    let character: Character
    let inviteID: UUID
    let index: Int

    var body: some View {
        Text(String(character))
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
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
            profileStatus: .complete
        ),
        onRefreshAccess: {}
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
