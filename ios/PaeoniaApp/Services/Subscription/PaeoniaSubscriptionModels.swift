import Foundation

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

nonisolated enum PaeoniaPurchaseError: Error, Equatable {
    case productUnavailable
    case userNotConfigured
    case invalidUserID
    case verificationFailed
    case serverConfirmationFailed
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
