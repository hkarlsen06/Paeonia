import SwiftUI

/// The centered confirmations the paywall can open: delete the account, leave
/// the relationship, and join through a previewed invite. Nothing happens until
/// the user picks the action in the alert.
struct PaywallConfirmationAlerts: ViewModifier {
    @Binding var isConfirmingDelete: Bool
    @Binding var isConfirmingUnpair: Bool
    @Binding var isConfirmingInvite: Bool
    let partnerName: String
    let invitePreview: PairingInvitePreview?
    let onDeleteAccount: () -> Void
    let onUnpair: () -> Void
    let onAcceptInvite: () -> Void
    let onCancelInvite: () -> Void

    func body(content: Content) -> some View {
        content
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
            .alert(Text(.pairingUnpairConfirmTitle(partnerName)), isPresented: $isConfirmingUnpair) {
                Button(role: .destructive, action: onUnpair) {
                    Text(.pairingUnpairConfirmAction)
                }
                Button(role: .cancel, action: {}) {
                    Text(.pairingUnpairConfirmCancel)
                }
            } message: {
                Text(.pairingUnpairConfirmMessage(partnerName))
            }
            .alert(
                Text(PaywallInviteConfirmation.title(for: invitePreview)),
                isPresented: $isConfirmingInvite
            ) {
                Button(action: onAcceptInvite) {
                    Text(.paywallInviteConfirmAction)
                }
                Button(role: .cancel, action: onCancelInvite) {
                    Text(.paywallInviteConfirmCancel)
                }
            } message: {
                Text(PaywallInviteConfirmation.message(for: invitePreview))
            }
    }
}
