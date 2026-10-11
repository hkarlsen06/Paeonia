import SwiftUI

/// The buttons pinned to the bottom of the invite screen. Share is the main action.
/// Copy, new code, and "have a code" are quiet text buttons that still get full-size
/// tap targets.
struct PairingInviteActionCluster: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let invite: PairingInvite
    let didCopyCode: Bool
    let isBusy: Bool
    let isJoining: Bool
    let onCopy: () -> Void
    let onNewCode: () -> Void
    let onEnterCode: () -> Void

    private var quietRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            shareButton

            quietRowLayout {
                quietButton(
                    title: didCopyCode ? .pairingInviteCopiedButton : .pairingInviteCopyButton,
                    systemImage: didCopyCode ? "checkmark.circle.fill" : "doc.on.doc.fill",
                    action: onCopy
                )

                quietButton(
                    title: .pairingInviteNewCodeButton,
                    systemImage: "arrow.clockwise",
                    action: onNewCode
                )
            }

            enterCodeButton
        }
        .padding(.top, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
    }

    private var shareButton: some View {
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
        .disabled(isBusy)
        .accessibilityIdentifier("pairing.share")
    }

    private func quietButton(
        title: LocalizedStringResource,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isBusy)
    }

    private var enterCodeButton: some View {
        Button(action: onEnterCode) {
            HStack(spacing: PaeoniaSpacing.space8) {
                if isJoining {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.paeoniaTextSecondary)
                        .accessibilityHidden(true)
                }

                Text(.pairingInviteJoinButton)
            }
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isBusy)
        .accessibilityIdentifier("pairing.enterCode")
    }
}
