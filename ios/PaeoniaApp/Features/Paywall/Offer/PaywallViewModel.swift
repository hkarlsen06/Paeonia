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
    private(set) var isPreviewingInvite = false
    private(set) var isAcceptingInvite = false
    private(set) var isLeavingRelationship = false
    private(set) var error: PaywallError?
    private(set) var purchaseSucceeded = false
    private(set) var invitePreview: PairingInvitePreview?

    private var previewedInviteCode: String?
    /// Last fully resolved eligibility snapshot. Keep it in place while StoreKit
    /// refreshes so an already-presented paywall never flips between trial and
    /// non-trial copy mid-refresh.
    private var eligibleFreeTrials = [PaeoniaSubscriptionProductID: PaeoniaFreeTrial]()

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
        eligibleFreeTrials[selectedProductID]
    }

    var selectedProductID: PaeoniaSubscriptionProductID {
        switch billingPeriod {
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
            if !succeeded {
                error = .purchaseNotConfirmed
            }
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

    /// Looks up a live invite before any relationship is created. The preview is
    /// retained with the exact normalized code so the UI can show the inviter and
    /// ask for an explicit confirmation before calling `acceptPreviewedInvite()`.
    func previewInvite(codeInput: String) async -> PairingInvitePreview? {
        guard !isPreviewingInvite, !isAcceptingInvite else {
            return nil
        }

        guard let pairingService else {
            error = .invitePreviewFailed
            return nil
        }

        isPreviewingInvite = true
        error = nil
        invitePreview = nil
        previewedInviteCode = nil

        do {
            let inviteCode = try PairingInviteCode.normalized(codeInput)
            guard let preview = try await pairingService.previewInvite(codeInput: inviteCode) else {
                error = .inviteUnavailable
                isPreviewingInvite = false
                return nil
            }

            invitePreview = preview
            previewedInviteCode = inviteCode
            isPreviewingInvite = false
            return preview
        } catch is PairingInviteCodeError {
            self.error = .inviteInvalid
            isPreviewingInvite = false
            return nil
        } catch is CancellationError {
            isPreviewingInvite = false
            return nil
        } catch {
            self.error = .invitePreviewFailed
            isPreviewingInvite = false
            return nil
        }
    }

    /// Accepts only the invite that was successfully previewed. Keeping this gate in
    /// the view model prevents another call site from accidentally restoring the old
    /// enter-code-and-immediately-pair behavior.
    func acceptPreviewedInvite() async -> Bool {
        guard !isPreviewingInvite,
              !isAcceptingInvite,
              let pairingService,
              invitePreview != nil,
              let previewedInviteCode
        else {
            error = .inviteUnavailable
            return false
        }

        isAcceptingInvite = true
        error = nil

        do {
            let operation = operationProvider.makeOperation()
            _ = try await pairingService.acceptInvite(
                codeInput: previewedInviteCode,
                operation: operation,
                startedOn: nil
            )
            isAcceptingInvite = false
            clearInvitePreview()
            return true
        } catch is CancellationError {
            isAcceptingInvite = false
            return false
        } catch {
            self.error = .inviteAcceptFailed
            isAcceptingInvite = false
            return false
        }
    }

    func clearInvitePreview() {
        invitePreview = nil
        previewedInviteCode = nil
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

extension PaywallViewModel {
    func loadProducts() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        error = nil

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

enum PaywallError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed
    case purchaseLinkedToAnotherAccount
    case noPurchasesToRestore
    case restoreFailed
    case inviteInvalid
    case inviteUnavailable
    case invitePreviewFailed
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
