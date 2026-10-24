import Foundation

/// The access a person has on their own, apart from what a partner's subscription
/// covers. It decides what leaving the relationship means for them and whether
/// Apple's subscription sheet has anything of theirs to show.
nonisolated enum OwnAccess: Equatable, Sendable {
    /// They pay through the App Store. The subscription keeps running if they
    /// leave the relationship, and only they can cancel it.
    case appStoreSubscription
    /// Access Paeonia gave them, such as lifetime access or access for App Review.
    case grant
    /// Nothing of their own. A partner's subscription may still cover them.
    case nothing

    init(_ entitlement: RemoteUserEntitlement?) {
        guard let entitlement, entitlement.isEntitled else {
            self = .nothing
            return
        }
        self = entitlement.source == "storekit" ? .appStoreSubscription : .grant
    }
}
