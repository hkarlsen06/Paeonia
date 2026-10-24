import StoreKit
import SwiftUI

/// Opens Apple's subscription sheet from the invite screen, for someone who left a
/// relationship and still pays. It sits below the first screen, so it is there
/// for whoever scrolls to it without competing with the invite.
struct PairingInviteManageSubscriptionButton: View {
    @State private var isManagingSubscription = false

    var body: some View {
        Button {
            isManagingSubscription = true
        } label: {
            Text(.paywallManageSubscription)
                .font(PaeoniaTypography.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.paeoniaAccentPrimary)
        .accessibilityIdentifier("pairing.invite.manageSubscription")
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
    }
}
