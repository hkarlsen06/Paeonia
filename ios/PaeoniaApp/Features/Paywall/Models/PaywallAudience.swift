import Foundation

/// Who the paywall is being shown to. The paywall serves two distinct situations,
/// and the copy plus available actions differ between them:
///
/// - `.unpaired`: signed in but not yet paired. This is the acquisition paywall,
///   and it also offers invite-code entry so the user can join a partner instead.
/// - `.unpairedWithDrawing`: the same, for someone whose first drawing for their
///   partner waits on this phone to be sent. The copy says it is ready.
/// - `.paired`: in an active relationship, but the couple has no active
///   subscription. The copy makes it clear they are still paired, and the footer
///   offers to unpair. Invite entry is hidden because they already have a partner.
///   `lapsedAccess` says whether this person paid, and the header and actions
///   follow it.
nonisolated enum PaywallAudience: Equatable, Sendable {
    case unpaired
    case unpairedWithDrawing
    case paired(partnerName: String?, lapsedAccess: LapsedAccess)

    var allowsInviteEntry: Bool {
        switch self {
        case .unpaired, .unpairedWithDrawing:
            true
        case .paired:
            false
        }
    }

    var isPaired: Bool {
        switch self {
        case .unpaired, .unpairedWithDrawing:
            false
        case .paired:
            true
        }
    }

    /// Apple is still retrying this person's payment. The paywall sends them to
    /// the App Store to fix it instead of offering plans to buy again.
    var asksToUpdatePayment: Bool {
        if case .paired(_, .paymentFailed) = self { true } else { false }
    }

    /// This person's own App Store subscription ended, so Apple's subscription
    /// sheet has something of theirs to show.
    var offersManageSubscription: Bool {
        if case .paired(_, .subscriptionEnded) = self { true } else { false }
    }

    var headline: LocalizedStringResource {
        switch self {
        case .unpaired:
            .paywallHeadline
        case .unpairedWithDrawing:
            .paywallDrawingReadyHeadline
        case .paired(_, .partnerCovered):
            .paywallPairedHeadline
        case .paired(_, .subscriptionEnded):
            .paywallPairedSubscriptionEndedHeadline
        case .paired(_, .paymentFailed):
            .paywallPairedPaymentFailedHeadline
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .unpaired:
            .paywallSubtitle
        case .unpairedWithDrawing:
            .paywallDrawingReadyMessage
        case .paired(_, .partnerCovered):
            .paywallPairedMessage(partnerNameForCopy)
        case .paired(_, .subscriptionEnded):
            .paywallPairedSubscriptionEndedMessage(partnerNameForCopy)
        case .paired(_, .paymentFailed):
            .paywallPairedPaymentFailedMessage(partnerNameForCopy)
        }
    }

    /// The partner's display name for copy, falling back to a neutral phrase when
    /// the name has not loaded yet.
    var partnerNameForCopy: String {
        switch self {
        case .unpaired, .unpairedWithDrawing:
            return String(localized: .paywallPairedPartnerFallback)
        case let .paired(partnerName, _):
            return partnerName?.trimmedNonEmpty ?? String(localized: .paywallPairedPartnerFallback)
        }
    }
}
