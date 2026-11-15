import SwiftUI

/// What the partner just did, in a glass capsule on the call while it covers the partner's avatar,
/// as the avatar would say it. A tap opens it.
struct CallCallout: View {
    let callout: PresenceCallout
    let partnerName: String
    let open: (PresenceDestination) -> Void

    var body: some View {
        PresenceCalloutContent(callout: callout, partnerName: partnerName, canOpen: callout.destination != nil) {
            if let destination = callout.destination { open(destination) }
        }
        .padding(.vertical, PaeoniaSpacing.space8)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
