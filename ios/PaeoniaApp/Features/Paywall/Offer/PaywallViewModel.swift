import Foundation
import Observation
#if DEBUG
import OSLog
#endif
import StoreKit

@MainActor
@Observable
final class PaywallViewModel: PresentationReadinessProviding {
    #if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Paywall"
    )
    #endif

    var billingPeriod: PaeoniaBillingPeriod = .monthly
    private(set) var isLoading = false
    private(set) var hasFinishedLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isAcceptingInvite = false
    private(set) var isLeavingRelationship = false
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

    var isPresentationReady: Bool {
        hasLoadedProducts || hasFinishedLoadingProducts
    }

    func loadProducts() async {
        guard !isLoading, !isPresentationReady else {
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

        hasFinishedLoadingProducts = true
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
            self.error = Self.paywallError(forPurchaseError: error)
            isPurchasing = false
            return false
        } catch {
            Self.logDiagnosticReason(from: error)
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
        } catch let error as PaeoniaPurchaseError {
            self.error = Self.paywallError(forRestoreError: error)
            isLoading = false
            return false
        } catch {
            Self.logDiagnosticReason(from: error)
            self.error = .restoreFailed
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

    /// Ends the current pairing. Used from the paired paywall footer, where a
    /// couple is linked but no one has an active subscription. On success the root
    /// re-resolves access and the user lands back in the unpaired flow.
    func leaveRelationship() async -> Bool {
        guard let pairingService else {
            error = .unpairFailed
            return false
        }

        isLeavingRelationship = true
        error = nil

        do {
            let operation = operationProvider.makeOperation()
            _ = try await pairingService.leaveRelationship(operation: operation)
            isLeavingRelationship = false
            return true
        } catch {
            self.error = .unpairFailed
            isLeavingRelationship = false
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private static func paywallError(forPurchaseError error: PaeoniaPurchaseError) -> PaywallError {
        logDiagnosticReason(from: error)

        switch error {
        case .purchaseLinkedToAnotherAccount:
            return .purchaseLinkedToAnotherAccount
        default:
            return .purchaseNotConfirmed
        }
    }

    private static func paywallError(forRestoreError error: PaeoniaPurchaseError) -> PaywallError {
        logDiagnosticReason(from: error)

        switch error {
        case .purchaseLinkedToAnotherAccount:
            return .purchaseLinkedToAnotherAccount
        default:
            return .restoreFailed
        }
    }

    private static func logDiagnosticReason(from error: Error) {
        #if DEBUG
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.nilIfBlank {
            logger.debug("\(description, privacy: .public)")
            return
        }

        if let description = String(describing: error).nilIfBlank {
            logger.debug("\(description, privacy: .public)")
        }
        #endif
    }
}

enum PaywallError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed
    case purchaseLinkedToAnotherAccount
    case noPurchasesToRestore
    case restoreFailed
    case inviteInvalid
    case inviteAcceptFailed
    case unpairFailed

    var message: String {
        switch self {
        case .productsUnavailable:
            String(localized: .paywallErrorProductsUnavailable)
        case .purchaseNotConfirmed:
            String(localized: .paywallErrorPurchaseNotConfirmed)
        case .purchaseLinkedToAnotherAccount:
            String(localized: .paywallErrorPurchaseLinkedToAnotherAccount)
        case .noPurchasesToRestore:
            String(localized: .paywallErrorNoPurchases)
        case .restoreFailed:
            String(localized: .paywallErrorRestoreFailed)
        case .inviteInvalid:
            String(localized: .paywallErrorInviteInvalid)
        case .inviteAcceptFailed:
            String(localized: .paywallErrorInviteAcceptFailed)
        case .unpairFailed:
            String(localized: .paywallErrorUnpairFailed)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
