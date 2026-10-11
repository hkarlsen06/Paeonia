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
    private(set) var isRestoring = false
    private(set) var isPreviewingInvite = false
    private(set) var isAcceptingInvite = false
    private(set) var isLeavingRelationship = false
    private(set) var error: PaywallError?
    private(set) var purchaseSucceeded = false
    private(set) var invitePreview: PairingInvitePreview?
    /// True after a preview proved the code itself is wrong or expired, as opposed
    /// to a network failure. The view stops remembering such a code.
    private(set) var lastInviteCodeWasUnusable = false

    private var previewedInviteCode: String?
    /// An accept whose answer never arrived, so it may have paired the couple.
    /// Retrying the same code reuses its operation, and the server replays the
    /// stored result instead of failing because the couple now exists. The retry
    /// also skips the preview, which would now report the used invite as gone.
    private var unconfirmedAccept: UnconfirmedInviteAccept?
    /// Last fully resolved eligibility snapshot. Keep it in place while StoreKit
    /// refreshes so an already-presented paywall never flips between trial and
    /// non-trial copy mid-refresh.
    private var eligibleFreeTrials = [PaeoniaSubscriptionProductID: PaeoniaFreeTrial]()
    /// How long the first frame may wait for StoreKit. Restore, sign out, and the
    /// legal links must never stay hidden behind a slow App Store response.
    private let firstPresentationDeadline: Duration

    private let storeKitService: any PaeoniaStoreKitServicing
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any PairingClientOperationProviding

    init(
        userID: String?,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil,
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil,
        firstPresentationDeadline: Duration = .seconds(5)
    ) {
        self.firstPresentationDeadline = firstPresentationDeadline
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        self.pairingService = pairingService ?? (try? RemotePairingService.live())
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

    /// A purchase or restore is talking to the App Store. Only one runs at a time.
    var isBusyWithStore: Bool {
        isPurchasing || isRestoring
    }

    func purchaseSelectedProduct() async -> Bool {
        guard !isBusyWithStore else {
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
        guard !isBusyWithStore else {
            return false
        }

        isPurchasing = true
        error = nil
        defer { isPurchasing = false }

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
        guard !isBusyWithStore else {
            return false
        }

        isRestoring = true
        error = nil
        defer { isRestoring = false }

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
        guard !isLeavingRelationship else {
            return false
        }

        guard let pairingService else {
            error = .unpairFailed
            return false
        }

        isLeavingRelationship = true
        error = nil
        defer { isLeavingRelationship = false }

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
        case .serverConfirmationFailed:
            // Apple charged the user and only our confirmation failed. The
            // transaction stays unfinished, and Restore sends it again.
            return .purchaseNotFinished
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

// MARK: - Invite entry

extension PaywallViewModel {
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
        lastInviteCodeWasUnusable = false
        defer { isPreviewingInvite = false }

        do {
            let inviteCode = try PairingInviteCode.normalized(codeInput)
            if let unconfirmedAccept, unconfirmedAccept.code == inviteCode {
                invitePreview = unconfirmedAccept.preview
                previewedInviteCode = inviteCode
                return unconfirmedAccept.preview
            }

            guard let preview = try await pairingService.previewInvite(codeInput: inviteCode) else {
                error = .inviteUnavailable
                lastInviteCodeWasUnusable = true
                return nil
            }

            invitePreview = preview
            previewedInviteCode = inviteCode
            return preview
        } catch is PairingInviteCodeError {
            self.error = .inviteInvalid
            lastInviteCodeWasUnusable = true
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            self.error = .invitePreviewFailed
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
              let invitePreview,
              let previewedInviteCode
        else {
            error = .inviteUnavailable
            return false
        }

        isAcceptingInvite = true
        error = nil
        defer { isAcceptingInvite = false }

        let operation = unconfirmedAccept?.code == previewedInviteCode
            ? unconfirmedAccept?.operation ?? operationProvider.makeOperation()
            : operationProvider.makeOperation()

        do {
            _ = try await pairingService.acceptInvite(
                codeInput: previewedInviteCode,
                operation: operation,
                startedOn: nil
            )
            unconfirmedAccept = nil
            clearInvitePreview()
            return true
        } catch let error as PaeoniaConvexError {
            // The server answered, so nothing was saved and the next try starts
            // fresh. Only a lost answer leaves the outcome unknown.
            if case .server = error {
                unconfirmedAccept = nil
            } else {
                rememberUnconfirmedAccept(previewedInviteCode, invitePreview, operation)
            }
            self.error = .inviteAcceptFailed
            return false
        } catch is CancellationError {
            rememberUnconfirmedAccept(previewedInviteCode, invitePreview, operation)
            return false
        } catch {
            rememberUnconfirmedAccept(previewedInviteCode, invitePreview, operation)
            self.error = .inviteAcceptFailed
            return false
        }
    }

    private func rememberUnconfirmedAccept(
        _ code: String,
        _ preview: PairingInvitePreview,
        _ operation: PairingClientOperation
    ) {
        unconfirmedAccept = UnconfirmedInviteAccept(code: code, preview: preview, operation: operation)
    }

    func clearInvitePreview() {
        invitePreview = nil
        previewedInviteCode = nil
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

private struct UnconfirmedInviteAccept {
    let code: String
    let preview: PairingInvitePreview
    let operation: PairingClientOperation
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
