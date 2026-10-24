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
nonisolated enum PaywallAudience: Equatable, Sendable {
    case unpaired
    case unpairedWithDrawing
    case paired(partnerName: String?)

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

    /// The plain unpaired offer has no headline. The logo above already says what
    /// Paeonia is, and a shorter header keeps the plans and the trial reminder
    /// above the buy button.
    var headline: LocalizedStringResource? {
        switch self {
        case .unpaired:
            nil
        case .unpairedWithDrawing:
            .paywallDrawingReadyHeadline
        case .paired:
            .paywallPairedHeadline
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .unpaired:
            .paywallSubtitle
        case .unpairedWithDrawing:
            .paywallDrawingReadyMessage
        case .paired:
            .paywallPairedMessage(partnerNameForCopy)
        }
    }

    /// The partner's display name for copy, falling back to a neutral phrase when
    /// the name has not loaded yet.
    var partnerNameForCopy: String {
        switch self {
        case .unpaired, .unpairedWithDrawing:
            return String(localized: .paywallPairedPartnerFallback)
        case let .paired(partnerName):
            return partnerName?.trimmedNonEmpty ?? String(localized: .paywallPairedPartnerFallback)
        }
    }
}
