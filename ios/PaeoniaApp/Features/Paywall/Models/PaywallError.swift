import Foundation

enum PaywallError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed
    /// Apple took the payment, but the server has not confirmed it yet.
    case purchaseNotFinished(PaeoniaFailure)
    /// Ask to Buy or another approval step. Not a failure for the user.
    case purchasePendingApproval
    case purchaseLinkedToAnotherAccount
    case noPurchasesToRestore
    case restoreFailed
    case unpairFailed

    /// Shown with the calm info banner instead of the error one.
    var isInformational: Bool {
        self == .purchasePendingApproval
    }

    var bannerContent: PaeoniaBannerContent {
        isInformational
            ? .info(title: title, message: message)
            : .error(title: title, message: message, timing: staysUntilDismissed ? .untilDismissed : .standard)
    }

    /// The payment went through but did not open Paeonia, or the fix is with
    /// support. The person needs the steps after the banner would have gone.
    private var staysUntilDismissed: Bool {
        switch self {
        case .purchaseNotFinished, .purchaseLinkedToAnotherAccount:
            true
        default:
            false
        }
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
        case let .purchaseNotFinished(failure):
            // Only a phone without a connection is told to check it.
            String(
                localized: failure == .offline
                    ? .paywallErrorPurchaseNotFinishedMessage
                    : .paywallErrorPurchaseNotFinishedRetryMessage
            )
        case .purchasePendingApproval:
            String(localized: .paywallPurchasePendingMessage)
        case .purchaseLinkedToAnotherAccount:
            String(localized: .paywallErrorPurchaseLinkedToAnotherAccount)
        case .noPurchasesToRestore:
            String(localized: .paywallErrorNoPurchases)
        case .restoreFailed:
            String(localized: .paywallErrorRestoreFailed)
        case .unpairFailed:
            String(localized: .pairingUnpairFailed)
        }
    }
}
