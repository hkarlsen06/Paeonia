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

    var approximateDayCount: Int {
        switch unit {
        case .day:
            value
        case .week:
            value * 7
        case .month:
            value * 30
        case .year:
            value * 365
        }
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
    let ok: Bool?
    let error: String?

    var isConfirmed: Bool {
        ok == true && error == nil
    }
}
