import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PaywallViewModel {
    var billingPeriod: PaeoniaBillingPeriod = .monthly
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var error: PaywallError?
    private(set) var purchaseSucceeded = false

    private let storeKitService: any PaeoniaStoreKitServicing

    init(
        userID: String?,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil
    ) {
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared

        if let userID {
            self.storeKitService.configure(userID: userID)
        }
    }

    var currentProduct: Product? {
        storeKitService.product(for: selectedProductID)
    }

    var currentFreeTrial: PaeoniaFreeTrial? {
        guard let offer = currentProduct?.subscription?.introductoryOffer else {
            return nil
        }

        return PaeoniaFreeTrial(offer: offer)
    }

    var selectedProductID: PaeoniaSubscriptionProductID {
        switch billingPeriod {
        case .monthly:
            .coupleMonthly
        case .yearly:
            .coupleYearly
        }
    }

    var hasLoadedProducts: Bool {
        !storeKitService.products.isEmpty
    }

    func loadProducts() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        error = nil

        do {
            try await storeKitService.loadProducts()
            if storeKitService.products.isEmpty {
                error = .productsUnavailable
            }
        } catch {
            self.error = .productsUnavailable
        }

        isLoading = false
    }

    func purchaseSelectedProduct() async -> Bool {
        guard let currentProduct else {
            error = .productsUnavailable
            return false
        }

        isPurchasing = true
        error = nil

        do {
            let succeeded = try await storeKitService.purchase(currentProduct)
            purchaseSucceeded = succeeded
            isPurchasing = false
            return succeeded
        } catch {
            self.error = .purchaseNotConfirmed
            isPurchasing = false
            return false
        }
    }

    func restorePurchases() async -> Bool {
        isLoading = true
        error = nil

        do {
            let restored = try await storeKitService.restorePurchases()
            purchaseSucceeded = restored
            if !restored {
                error = .noPurchasesToRestore
            }
            isLoading = false
            return restored
        } catch {
            self.error = .restoreFailed
            isLoading = false
            return false
        }
    }

    func clearError() {
        error = nil
    }
}

enum PaywallError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed
    case noPurchasesToRestore
    case restoreFailed

    var message: LocalizedStringResource {
        switch self {
        case .productsUnavailable:
            .paywallErrorProductsUnavailable
        case .purchaseNotConfirmed:
            .paywallErrorPurchaseNotConfirmed
        case .noPurchasesToRestore:
            .paywallErrorNoPurchases
        case .restoreFailed:
            .paywallErrorRestoreFailed
        }
    }
}
