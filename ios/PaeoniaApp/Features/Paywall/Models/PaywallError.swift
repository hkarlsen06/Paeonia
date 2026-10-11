import Foundation

enum PaywallError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed
    /// Apple took the payment, but the server has not confirmed it yet.
    case purchaseNotFinished
    /// Ask to Buy or another approval step. Not a failure for the user.
    case purchasePendingApproval
    case purchaseLinkedToAnotherAccount
    case noPurchasesToRestore
    case restoreFailed
    case inviteInvalid
    case inviteUnavailable
    case invitePreviewFailed
    case inviteAcceptFailed
    case unpairFailed

    /// Shown with the calm info banner instead of the error one.
    var isInformational: Bool {
        self == .purchasePendingApproval
    }

    var bannerContent: PaeoniaBannerContent {
        isInformational
            ? .info(title: title, message: message)
            : .error(title: title, message: message)
    }

    var title: String? {
        switch self {
        case .purchasePendingApproval:
            String(localized: .paywallPurchasePendingTitle)
        case .purchaseNotFinished:
            String(localized: .paywallErrorPurchaseNotFinishedTitle)
        default:
            nil
        }
    }

    var message: String {
        switch self {
        case .productsUnavailable:
            String(localized: .paywallErrorProductsUnavailable)
        case .purchaseNotConfirmed:
            String(localized: .paywallErrorPurchaseNotConfirmed)
        case .purchaseNotFinished:
            String(localized: .paywallErrorPurchaseNotFinishedMessage)
        case .purchasePendingApproval:
            String(localized: .paywallPurchasePendingMessage)
        case .purchaseLinkedToAnotherAccount:
            String(localized: .paywallErrorPurchaseLinkedToAnotherAccount)
        case .noPurchasesToRestore:
            String(localized: .paywallErrorNoPurchases)
        case .restoreFailed:
            String(localized: .paywallErrorRestoreFailed)
        case .inviteInvalid:
            String(localized: .paywallErrorInviteInvalid)
        case .inviteUnavailable:
            String(localized: .paywallErrorInviteUnavailable)
        case .invitePreviewFailed:
            String(localized: .paywallErrorInvitePreviewFailed)
        case .inviteAcceptFailed:
            String(localized: .paywallErrorInviteAcceptFailed)
        case .unpairFailed:
            String(localized: .pairingUnpairFailed)
        }
    }
}
