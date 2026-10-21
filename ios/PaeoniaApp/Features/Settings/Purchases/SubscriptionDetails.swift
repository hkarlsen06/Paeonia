import Foundation

/// What Paeonia's server has on record for this person's access, in the words the
/// subscription screen shows. Apple stays the source of truth for billing, so the
/// screen lets people compare this record with what Apple shows.
nonisolated struct SubscriptionDetails: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case active
        /// Apple could not take the last payment. Access may still continue for a
        /// short grace period.
        case paymentProblem
        case ended
        case refunded
        case lifetime
        /// Access Paeonia gave directly, such as for App Review or testing.
        case freeAccess
        case none
    }

    enum Payer: Equatable, Sendable {
        case you
        case partner(name: String?)
    }

    let status: Status
    let billingPeriod: PaeoniaBillingPeriod?
    let periodEnd: Date?
    /// Who the record says pays. Set only when the access covers the couple.
    let payer: Payer?

    /// A couple subscription paid by either partner covers both, so the couple's
    /// record comes first. Without it, the person's own record explains why they
    /// have no access, for example an ended or refunded subscription.
    init(snapshot: RemoteAccessSnapshot) {
        if let couple = snapshot.coupleEntitlement, couple.isEntitled {
            status = Self.status(source: couple.source, status: couple.status, isEntitled: true)
            billingPeriod = couple.billingPeriod.flatMap(PaeoniaBillingPeriod.init(rawValue:))
            periodEnd = status == .lifetime ? nil : couple.currentPeriodEnd
            payer = couple.coveringUserID == snapshot.userEntitlement?.userID
                ? .you
                : .partner(name: snapshot.relationshipState?.partnerName.display)
            return
        }

        let own = snapshot.userEntitlement
        status = Self.status(source: own?.source, status: own?.status, isEntitled: own?.isEntitled ?? false)
        billingPeriod = own?.billingPeriod.flatMap(PaeoniaBillingPeriod.init(rawValue:))
        periodEnd = status == .lifetime ? nil : own?.currentPeriodEnd
        payer = nil
    }

    private static func status(source: String?, status: String?, isEntitled: Bool) -> Status {
        guard let status else {
            return .none
        }
        if isEntitled {
            if status == "lifetime" {
                return .lifetime
            }
            if source != "storekit" {
                return .freeAccess
            }
            return status == "grace" ? .paymentProblem : .active
        }
        switch status {
        case "grace", "billing_retry":
            return .paymentProblem
        case "refunded":
            return .refunded
        default:
            return .ended
        }
    }
}
