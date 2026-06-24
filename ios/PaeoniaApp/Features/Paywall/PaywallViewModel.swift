import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PaywallViewModel {
    var billingPeriod: PaeoniaBillingPeriod = .monthly
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isAcceptingInvite = false
    private(set) var error: PaywallError?
    private(set) var purchaseSucceeded = false

    private let storeKitService: any PaeoniaStoreKitServicing
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any PairingClientOperationProviding

    init(
        userID: String?,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil,
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil
    ) {
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        self.pairingService = pairingService ?? (try? SupabasePairingService.live())
        self.operationProvider = operationProvider ?? PairingClientOperationFactory.shared

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
        } catch let error as PaeoniaPurchaseError {
            self.error = .purchaseNotConfirmed(error.confirmationReason ?? Self.diagnosticReason(from: error))
            isPurchasing = false
            return false
        } catch {
            self.error = .purchaseNotConfirmed(Self.diagnosticReason(from: error))
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
        } catch let error as PaeoniaPurchaseError {
            self.error = .restoreFailed(error.confirmationReason ?? Self.diagnosticReason(from: error))
            isLoading = false
            return false
        } catch {
            self.error = .restoreFailed(Self.diagnosticReason(from: error))
            isLoading = false
            return false
        }
    }

    func acceptInvite(codeInput: String) async -> Bool {
        guard let pairingService else {
            error = .inviteAcceptFailed
            return false
        }

        let startedOn = PairingStartDate(date: Date())
        isAcceptingInvite = true
        error = nil

        do {
            let inviteCode = try PairingInviteCode.normalized(codeInput)
            let operation = operationProvider.makeOperation()
            _ = try await pairingService.acceptInvite(
                codeInput: inviteCode,
                operation: operation,
                startedOn: startedOn
            )
            isAcceptingInvite = false
            return true
        } catch is PairingInviteCodeError {
            self.error = .inviteInvalid
            isAcceptingInvite = false
            return false
        } catch {
            self.error = .inviteAcceptFailed
            isAcceptingInvite = false
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private static func diagnosticReason(from error: Error) -> String? {
        #if DEBUG
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.nilIfBlank {
            return description
        }

        return String(describing: error).nilIfBlank
        #else
        return nil
        #endif
    }
}

enum PaywallError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed(String?)
    case noPurchasesToRestore
    case restoreFailed(String?)
    case inviteInvalid
    case inviteAcceptFailed

    var message: String {
        switch self {
        case .productsUnavailable:
            String(localized: .paywallErrorProductsUnavailable)
        case let .purchaseNotConfirmed(reason):
            Self.message(.paywallErrorPurchaseNotConfirmed, reason: reason)
        case .noPurchasesToRestore:
            String(localized: .paywallErrorNoPurchases)
        case let .restoreFailed(reason):
            Self.message(.paywallErrorRestoreFailed, reason: reason)
        case .inviteInvalid:
            String(localized: .paywallErrorInviteInvalid)
        case .inviteAcceptFailed:
            String(localized: .paywallErrorInviteAcceptFailed)
        }
    }

    private static func message(_ base: LocalizedStringResource, reason: String?) -> String {
        let baseMessage = String(localized: base)
        #if DEBUG
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else {
            return baseMessage
        }

        return "\(baseMessage)\n\n\(reason)"
        #else
        return baseMessage
        #endif
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
