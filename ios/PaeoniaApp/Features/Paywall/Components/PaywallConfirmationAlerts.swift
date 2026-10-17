import SwiftUI

/// The centered confirmations the paywall can open: delete the account and leave
/// the relationship. Nothing happens until the user picks the action in the alert.
struct PaywallConfirmationAlerts: ViewModifier {
    @Binding var isConfirmingDelete: Bool
    @Binding var isConfirmingUnpair: Bool
    let partnerName: String
    let onDeleteAccount: () -> Void
    let onUnpair: () -> Void

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
    }
}
