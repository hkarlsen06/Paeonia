import SwiftUI

#Preview {
    RootBrandedFrame {
        PaywallView(
            session: AuthSession(
                id: UUID().uuidString,
                provider: .apple,
                displayName: "Alvilde",
                timeZoneID: "Europe/Oslo",
                profilePhotoAssetID: nil,
                profileStatus: .complete
            ),
            audience: .unpaired,
            onPurchaseConfirmed: {},
            onInviteAccepted: {},
            onSignOut: {},
            onUnpaired: {},
            onDeleteAccount: {}
        )
    }
    .preferredColorScheme(.dark)
    .environment(PaeoniaBannerCenter())
}
