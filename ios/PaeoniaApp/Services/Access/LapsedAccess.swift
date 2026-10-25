import Foundation

/// This person's part in a couple whose access lapsed, so the paywall can speak to the one who
/// paid differently from the partner they covered. `OwnAccess` cannot tell them apart, because
/// neither has access after a lapse. The server still returns the person's newest entitlement row
/// when it grants nothing, so an App Store row means they paid.
nonisolated enum LapsedAccess: Equatable, Sendable {
    /// No App Store subscription of their own. A grant counts here too.
    case partnerCovered
    /// Their App Store subscription ended, expired, or was refunded or revoked.
    case subscriptionEnded
    /// Apple could not take their payment and is still retrying it, so buying again is the wrong
    /// step. Fixing the payment in the App Store brings access back.
    case paymentFailed

    init(_ entitlement: RemoteUserEntitlement?) {
        guard let entitlement, entitlement.source == "storekit" else {
            self = .partnerCovered
            return
        }
        self = entitlement.status == "billing_retry" ? .paymentFailed : .subscriptionEnded
    }
}
