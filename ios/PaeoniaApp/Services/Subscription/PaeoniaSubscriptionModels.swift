import Foundation
import StoreKit

nonisolated enum PaeoniaSubscriptionProductID: String, CaseIterable, Sendable {
    case coupleMonthly = "no.paeonia.couple"
    case coupleYearly = "no.paeonia.couple.year"

    var billingPeriod: PaeoniaBillingPeriod {
        switch self {
        case .coupleMonthly:
            .monthly
        case .coupleYearly:
            .yearly
        }
    }
}

nonisolated enum PaeoniaBillingPeriod: String, CaseIterable, Sendable {
    case monthly
    case yearly
}

/// One-time (consumable) products. Kept separate from the subscription IDs so the
/// restore-purchases flow, which only re-applies subscriptions, never trips over a
/// consumable that Apple never lists in `Transaction.currentEntitlements`.
nonisolated enum PaeoniaConsumableProductID: String, CaseIterable, Sendable {
    case streakRestore = "no.paeonia.streak.restore"
}

nonisolated struct PaeoniaFreeTrial: Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
    }

    let value: Int
    let unit: Unit

    init(value: Int, unit: Unit) {
        self.value = max(value, 1)
        self.unit = unit
    }

    init?(offer: Product.SubscriptionOffer) {
        guard offer.paymentMode == .freeTrial else {
            return nil
        }

        self.init(
            value: offer.period.value * offer.periodCount,
            unit: Self.unit(from: offer.period.unit)
        )
    }

    var localizedDurationText: String {
        "\(value) \(String(localized: unitLabel))"
    }

    private var unitLabel: LocalizedStringResource {
        switch unit {
        case .day:
            value == 1 ? .paywallTrialUnitDay : .paywallTrialUnitDays
        case .week:
            value == 1 ? .paywallTrialUnitWeek : .paywallTrialUnitWeeks
        case .month:
            value == 1 ? .paywallTrialUnitMonth : .paywallTrialUnitMonths
        case .year:
            value == 1 ? .paywallTrialUnitYear : .paywallTrialUnitYears
        }
    }

    private static func unit(from storeKitUnit: Product.SubscriptionPeriod.Unit) -> Unit {
        switch storeKitUnit {
        case .day:
            .day
        case .week:
            .week
        case .month:
            .month
        case .year:
            .year
        @unknown default:
            .day
        }
    }
}

nonisolated enum PaeoniaPurchaseError: Error, Equatable {
    case productUnavailable
    case userNotConfigured
    case invalidUserID
    case verificationFailed
    case serverConfirmationFailed(String?)
    case purchaseLinkedToAnotherAccount
    case purchaseFailed
    case restoreFailed
    /// The user closed an App Store sheet. Callers stay quiet about it.
    case cancelled
    /// The purchase is waiting for approval, for example by a parent through Ask
    /// to Buy. The transaction listener confirms it later if it is approved.
    case pendingApproval
    /// The streak could not be brought back — the offer had already closed or
    /// there was nothing to restore by the time the purchase was verified.
    case streakNotRestorable
}

nonisolated struct PaeoniaStoreKitUploadRequest: Encodable, Equatable {
    let jws: String
    let transactionId: String
    let originalTransactionId: String
    let productId: String
    let environment: String
    let priceDisplay: String?
}

nonisolated struct PaeoniaStoreKitUploadResponse: Decodable, Equatable {
    let entitled: Bool
}

nonisolated struct PaeoniaStreakRestoreUploadRequest: Encodable, Equatable {
    let jws: String
    let transactionId: String
    let originalTransactionId: String
    let productId: String
    let environment: String
}

nonisolated struct PaeoniaStreakRestoreUploadResponse: Decodable, Equatable {
    let restoredCount: Int
}
