import SwiftUI

#Preview {
    PaeoniaScreenFrame {
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
            onSubmitInviteCode: { _ in false },
            onSignOut: {},
            onUnpaired: {},
            onDeleteAccount: {}
        )
    }
    .preferredColorScheme(.dark)
    .environment(PaeoniaBannerCenter())
}
