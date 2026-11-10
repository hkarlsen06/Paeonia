import Foundation
import Observation
#if DEBUG
import OSLog
#endif
import StoreKit

@Observable
final class PaywallViewModel {
    #if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Paywall"
    )
    #endif

    /// The year starts selected. Its card comes first and costs less per month.
    var billingPeriod: PaeoniaBillingPeriod = .yearly
    private(set) var isLoading = false
    private(set) var hasFinishedLoadingProducts = false
    /// What the paywall is doing for the person. One action runs at a time, so a
    /// purchase, a restore and leaving the relationship never overlap.
    private(set) var runningAction: PaywallAction?
    private(set) var error: PaywallError?
    private(set) var purchaseSucceeded = false

    /// Last fully resolved eligibility snapshot. Keep it in place while StoreKit
    /// refreshes so an already-presented paywall never flips between trial and
    /// non-trial copy mid-refresh.
    private var eligibleFreeTrials = [PaeoniaSubscriptionProductID: PaeoniaFreeTrial]()
    /// How long the first frame may wait for StoreKit. Restore, sign out, and the
    /// legal links must never stay hidden behind a slow App Store response.
    private let firstPresentationDeadline: Duration

    private let storeKitService: any PaeoniaStoreKitServicing
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any SyncClientOperationProviding

    init(
        userID: String?,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil,
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        firstPresentationDeadline: Duration = .seconds(5)
    ) {
        self.firstPresentationDeadline = firstPresentationDeadline
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        self.pairingService = pairingService ?? (try? RemotePairingService.live())
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared

        if let userID {
            self.storeKitService.configure(userID: userID)
        }
    }

    var currentProduct: Product? {
        product(for: billingPeriod)
    }

    func product(for period: PaeoniaBillingPeriod) -> Product? {
        storeKitService.product(for: Self.productID(for: period))
    }

    func freeTrial(for period: PaeoniaBillingPeriod) -> PaeoniaFreeTrial? {
        eligibleFreeTrials[Self.productID(for: period)]
    }

    private static func productID(for period: PaeoniaBillingPeriod) -> PaeoniaSubscriptionProductID {
        switch period {
        case .monthly:
            .coupleMonthly
        case .yearly:
            .coupleYearly
        }
    }

    var isPresentationReady: Bool {
        // Products can publish before the asynchronous introductory-offer
        // eligibility check settles. Do not expose a first frame until both have
        // reached a stable result, otherwise an ineligible subscriber can briefly
        // see trial copy. This flag stays true during later refreshes.
        hasFinishedLoadingProducts
    }

    var isPurchasing: Bool { runningAction == .purchasing }
    var isRestoring: Bool { runningAction == .restoring }

    /// A purchase or restore is talking to the App Store.
    var isBusyWithStore: Bool {
        isPurchasing || isRestoring
    }

    func purchaseSelectedProduct() async -> Bool {
        guard runningAction == nil else {
            return false
        }

        guard let currentProduct else {
            error = .productsUnavailable
            return false
        }

        return await runPurchase { [storeKitService] in
            try await storeKitService.purchase(currentProduct)
        }
    }

    /// The purchase flow around one App Store call. Separate from the product
    /// lookup because unit tests cannot create a StoreKit `Product`.
    func runPurchase(_ purchase: () async throws -> Bool) async -> Bool {
        guard runningAction == nil else {
            return false
        }

        runningAction = .purchasing
        error = nil
        defer { runningAction = nil }

        do {
            // `false` means the user closed the App Store sheet, so say nothing.
            let succeeded = try await purchase()
            purchaseSucceeded = succeeded
            return succeeded
        } catch let error as PaeoniaPurchaseError {
            self.error = Self.paywallError(forPurchaseError: error)
            return false
        } catch {
            Self.logDiagnosticReason(from: error)
            self.error = .purchaseNotConfirmed
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard runningAction == nil else {
            return false
        }

        runningAction = .restoring
        error = nil
        defer { runningAction = nil }

        do {
            let restored = try await storeKitService.restorePurchases()
            purchaseSucceeded = restored
            if !restored {
                error = .noPurchasesToRestore
            }
            return restored
        } catch let error as PaeoniaPurchaseError {
            self.error = Self.paywallError(forRestoreError: error)
            return false
        } catch {
            Self.logDiagnosticReason(from: error)
            self.error = .restoreFailed
            return false
        }
    }

    /// Ends the current pairing. Used from the paired paywall footer, where a
    /// couple is linked but no one has an active subscription. On success the root
    /// re-resolves access and the user lands back in the unpaired flow.
    func leaveRelationship() async -> Bool {
        guard runningAction == nil else {
            return false
        }

        guard let pairingService else {
            error = .unpairFailed
            return false
        }

        runningAction = .leavingRelationship
        error = nil
        defer { runningAction = nil }

        do {
            let operation = operationProvider.makeOperation()
            _ = try await pairingService.leaveRelationship(operation: operation)
            return true
        } catch {
            self.error = .unpairFailed
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private static func paywallError(forPurchaseError error: PaeoniaPurchaseError) -> PaywallError? {
        logDiagnosticReason(from: error)

        switch error {
        case .cancelled:
            return nil
        case .pendingApproval:
            return .purchasePendingApproval
        case .purchaseLinkedToAnotherAccount:
            return .purchaseLinkedToAnotherAccount
        case let .serverConfirmationFailed(_, failure):
            // Apple charged the user and only our confirmation failed. The
            // transaction stays unfinished, and Restore sends it again.
            return .purchaseNotFinished(failure)
        default:
            return .purchaseNotConfirmed
        }
    }

    private static func paywallError(forRestoreError error: PaeoniaPurchaseError) -> PaywallError? {
        logDiagnosticReason(from: error)

        switch error {
        case .cancelled:
            return nil
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

extension PaywallViewModel {
    func loadProducts() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        error = nil

        // The first frame waits for a stable offer, but not forever. After the
        // deadline the paywall shows with "Loading price" and keeps loading.
        let deadline = Task { [weak self, firstPresentationDeadline] in
            try? await Task.sleep(for: firstPresentationDeadline)
            guard !Task.isCancelled else {
                return
            }
            self?.hasFinishedLoadingProducts = true
        }
        defer { deadline.cancel() }

        do {
            try await storeKitService.loadProducts()
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            let refreshedFreeTrials = await loadEligibleFreeTrials()
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            // Replace only after every product's eligibility has settled. Until
            // then the prior stable offer state remains visible during refreshes.
            eligibleFreeTrials = refreshedFreeTrials
            if storeKitService.products.isEmpty {
                error = .productsUnavailable
            }
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            self.error = .productsUnavailable
        }

        hasFinishedLoadingProducts = true
        isLoading = false
    }

    private func loadEligibleFreeTrials() async -> [PaeoniaSubscriptionProductID: PaeoniaFreeTrial] {
        var trials = [PaeoniaSubscriptionProductID: PaeoniaFreeTrial]()

        for productID in PaeoniaSubscriptionProductID.allCases {
            if let trial = await storeKitService.eligibleFreeTrial(for: productID) {
                trials[productID] = trial
            }
        }

        return trials
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PaywallAction: Equatable {
    case purchasing
    case restoring
    case leavingRelationship
}
