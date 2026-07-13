import Foundation

/// Who the paywall is being shown to. The paywall serves two distinct situations,
/// and the copy plus available actions differ between them:
///
/// - `.unpaired`: signed in but not yet paired. This is the acquisition paywall,
///   and it also offers invite-code entry so the user can join a partner instead.
/// - `.paired`: in an active relationship, but the couple has no active
///   subscription. The copy makes it clear they are still paired, and the footer
///   offers to unpair. Invite entry is hidden because they already have a partner.
nonisolated enum PaywallAudience: Equatable, Sendable {
    case unpaired
    case paired(partnerName: String?)

    var allowsInviteEntry: Bool {
        switch self {
        case .unpaired:
            true
        case .paired:
            false
        }
    }

    var isPaired: Bool {
        switch self {
        case .unpaired:
            false
        case .paired:
            true
        }
    }

    func headlineTitle(hasFreeTrial: Bool) -> LocalizedStringResource {
        switch self {
        case .unpaired:
            hasFreeTrial ? .paywallTrialTitle : .paywallTitle
        case .paired:
            .paywallPairedTitle(partnerNameForCopy)
        }
    }

    func subtitle(hasFreeTrial: Bool) -> LocalizedStringResource {
        switch (self, hasFreeTrial) {
        case (.unpaired, true):
            .paywallTrialSubtitle
        case (.unpaired, false):
            .paywallSubtitle
        case (.paired, true):
            .paywallPairedTrialSubtitle
        case (.paired, false):
            .paywallPairedSubtitle
        }
    }

    /// The partner's display name for copy, falling back to a neutral phrase when
    /// the name has not loaded yet.
    var partnerNameForCopy: String {
        switch self {
        case .unpaired:
            return String(localized: .paywallPairedPartnerFallback)
        case let .paired(partnerName):
            return partnerName?.trimmedNonEmpty ?? String(localized: .paywallPairedPartnerFallback)
        }
    }
}
