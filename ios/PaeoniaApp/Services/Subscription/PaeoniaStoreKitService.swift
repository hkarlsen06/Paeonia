import Foundation
import Observation
import StoreKit

extension Notification.Name {
    nonisolated static let paeoniaSubscriptionDidUpdate = Notification.Name(
        "paeonia.subscription.didUpdate"
    )
}

@MainActor
protocol PaeoniaStoreKitServicing: AnyObject {
    var products: [Product] { get }

    func configure(userID: String)
    func loadProducts() async throws
    /// Returns the configured free trial only when StoreKit says the current
    /// App Store account is eligible for the subscription group's introductory
    /// offer. A configured offer alone is not proof that this user can redeem it.
    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial?
    func product(for productID: PaeoniaSubscriptionProductID) -> Product?
    func product(for productID: PaeoniaConsumableProductID) -> Product?
    /// `true` once the server confirmed the purchase, `false` when the user
    /// cancelled. Throws `PaeoniaPurchaseError.pendingApproval` for Ask to Buy.
    func purchase(_ product: Product) async throws -> Bool
    /// `true` when a subscription for this account was confirmed. Throws
    /// `PaeoniaPurchaseError.cancelled` when the user closes the App Store sheet.
    func restorePurchases() async throws -> Bool
    /// Buys the streak-restore consumable and asks the server to bring the streak
    /// back. Returns the restored streak length, or `nil` if the user cancelled.
    func redeemStreakRestore() async throws -> Int?
    /// Re-applies any streak-restore purchase that was paid for but never
    /// confirmed (e.g. the app died mid-flow). Idempotent on the server. Returns
    /// the restored streak length if one was recovered.
    @discardableResult
    func recoverPendingStreakRestores() async -> Int?
}

extension PaeoniaStoreKitServicing {
    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? {
        guard let subscription = product(for: productID)?.subscription,
              let introductoryOffer = subscription.introductoryOffer,
              let configuredTrial = PaeoniaFreeTrial(offer: introductoryOffer)
        else {
            return nil
        }

        let isEligible = await subscription.isEligibleForIntroOffer
        return PaeoniaStoreKitOfferEligibility.freeTrial(
            configuredOffer: configuredTrial,
            isEligible: isEligible
        )
    }
}

/// Small value-level policy kept separate from StoreKit's opaque `Product` so the
/// distinction between a configured and an eligible offer has a focused regression
/// test. Production eligibility still comes directly from StoreKit above.
nonisolated enum PaeoniaStoreKitOfferEligibility {
    static func freeTrial(
        configuredOffer: PaeoniaFreeTrial?,
        isEligible: Bool
    ) -> PaeoniaFreeTrial? {
        guard isEligible else {
            return nil
        }
        return configuredOffer
    }
}

@MainActor
@Observable
final class PaeoniaStoreKitService: PaeoniaStoreKitServicing {
    static let shared = PaeoniaStoreKitService()

    private(set) var products: [Product] = []

    private let clientProvider: PaeoniaConvexClientProvider
    private var userID: String?
    private var appAccountToken: UUID?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    init(clientProvider: PaeoniaConvexClientProvider = .shared) {
        self.clientProvider = clientProvider
    }

    func configure(userID: String) {
        guard self.userID != userID else {
            return
        }

        self.userID = userID
        appAccountToken = nil
        startTransactionListener()
    }

    func stopTransactionListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
        userID = nil
        appAccountToken = nil
    }

    func loadProducts() async throws {
        let productIDs = PaeoniaSubscriptionProductID.allCases.map(\.rawValue)
            + PaeoniaConsumableProductID.allCases.map(\.rawValue)
        products = try await Product.products(for: productIDs)
    }

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? {
        products.first { $0.id == productID.rawValue }
    }

    func product(for productID: PaeoniaConsumableProductID) -> Product? {
        products.first { $0.id == productID.rawValue }
    }

    /// Returns `true` once the server has confirmed the purchase and `false` when
    /// the user closed the App Store sheet. Throws `.pendingApproval` when the
    /// purchase waits for approval (Ask to Buy); the transaction listener confirms
    /// it later. A purchase that went through but could not be confirmed stays
    /// unfinished and throws `.serverConfirmationFailed`, so Restore can retry it.
    func purchase(_ product: Product) async throws -> Bool {
        let token = try await configuredAppAccountToken()
        let purchaseResult: Product.PurchaseResult

        do {
            purchaseResult = try await product.purchase(options: [.appAccountToken(token)])
        } catch StoreKitError.userCancelled {
            return false
        } catch {
            throw PaeoniaPurchaseError.purchaseFailed
        }

        switch purchaseResult {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw PaeoniaPurchaseError.verificationFailed
            }

            try await confirmPaidPurchase(
                transaction: transaction,
                jwsRepresentation: verification.jwsRepresentation,
                priceDisplay: product.displayPrice
            )

            await transaction.finish()

            return true
        case .pending:
            throw PaeoniaPurchaseError.pendingApproval
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    /// Asks the App Store for this Apple ID's subscriptions and confirms the ones
    /// bought with this account. Returns `false` when there is nothing to restore.
    /// Throws `.purchaseLinkedToAnotherAccount` when the only subscription belongs
    /// to a different Paeonia account, and `.cancelled` when the user closes the
    /// App Store sign-in sheet.
    func restorePurchases() async throws -> Bool {
        let token = try await configuredAppAccountToken()

        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            throw PaeoniaPurchaseError.cancelled
        } catch {
            throw PaeoniaPurchaseError.restoreFailed
        }

        var didConfirmPurchase = false
        var foundAnotherAccountsPurchase = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  PaeoniaSubscriptionProductID(rawValue: transaction.productID) != nil
            else {
                continue
            }

            guard transaction.appAccountToken == token else {
                if transaction.appAccountToken != nil {
                    foundAnotherAccountsPurchase = true
                }
                continue
            }

            let displayPrice = productDisplayPrice(for: transaction.productID)
            try await confirm(
                transaction: transaction,
                jwsRepresentation: result.jwsRepresentation,
                priceDisplay: displayPrice
            )
            // A purchase that was paid for but never confirmed is still
            // unfinished. Now that the server has it, finish it.
            await transaction.finish()
            didConfirmPurchase = true
        }

        if !didConfirmPurchase && foundAnotherAccountsPurchase {
            throw PaeoniaPurchaseError.purchaseLinkedToAnotherAccount
        }

        return didConfirmPurchase
    }

    func redeemStreakRestore() async throws -> Int? {
        guard let product = product(for: .streakRestore) else {
            throw PaeoniaPurchaseError.productUnavailable
        }

        let token = try await configuredAppAccountToken()
        let purchaseResult: Product.PurchaseResult

        do {
            purchaseResult = try await product.purchase(options: [.appAccountToken(token)])
        } catch StoreKitError.userCancelled {
            return nil
        } catch {
            throw PaeoniaPurchaseError.purchaseFailed
        }

        switch purchaseResult {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw PaeoniaPurchaseError.verificationFailed
            }

            let restoredCount = try await confirmStreakRestore(
                transaction: transaction,
                jwsRepresentation: verification.jwsRepresentation
            )

            // Only consume the purchase once the server has applied it.
            await transaction.finish()

            return restoredCount
        case .pending:
            // Ask to Buy: the restore lands later through the transaction listener
            // if it is approved. Callers show that it is waiting, not a cancel.
            throw PaeoniaPurchaseError.pendingApproval
        case .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    @discardableResult
    func recoverPendingStreakRestores() async -> Int? {
        let token = try? await configuredAppAccountToken()
        var recoveredCount: Int?

        for await result in Transaction.unfinished {
            guard case let .verified(transaction) = result else {
                continue
            }

            guard PaeoniaConsumableProductID(rawValue: transaction.productID) != nil else {
                continue
            }

            if let token, let transactionToken = transaction.appAccountToken, transactionToken != token {
                continue
            }

            do {
                recoveredCount = try await confirmStreakRestore(
                    transaction: transaction,
                    jwsRepresentation: result.jwsRepresentation
                )
                await transaction.finish()
            } catch {
                // Leave it unfinished so the next attempt can retry; the server
                // restore is idempotent, so a replay never restores twice.
                recoveredCount = Self.pendingRestoreCount(recoveredCount, afterFailure: error)
            }
        }

        return recoveredCount
    }

    /// A paid restore that the server has not confirmed yet still counts as
    /// pending (0), so the sheet waits for it instead of selling a second one.
    /// A restore the server refused for good, or one that belongs to another
    /// account, does not hold up this person's purchase.
    static func pendingRestoreCount(_ count: Int?, afterFailure error: any Error) -> Int? {
        let refusedForGood: [PaeoniaPurchaseError] = [.streakNotRestorable, .purchaseLinkedToAnotherAccount]
        return refusedForGood.contains { $0 == error as? PaeoniaPurchaseError } ? count : count ?? 0
    }

    private func startTransactionListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard let self, !Task.isCancelled else {
                    return
                }
                await self.processTransactionUpdate(result)
            }

            for await result in Transaction.updates {
                guard let self, !Task.isCancelled else {
                    return
                }
                await self.processTransactionUpdate(result)
            }
        }
    }

    private func processTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else {
            return
        }

        do {
            let token = try await configuredAppAccountToken()
            guard transaction.appAccountToken == token else {
                return
            }

            if PaeoniaSubscriptionProductID(rawValue: transaction.productID) != nil {
                try await confirm(
                    transaction: transaction,
                    jwsRepresentation: result.jwsRepresentation,
                    priceDisplay: productDisplayPrice(for: transaction.productID)
                )
                await transaction.finish()
                NotificationCenter.default.post(name: .paeoniaSubscriptionDidUpdate, object: nil)
            } else if PaeoniaConsumableProductID(rawValue: transaction.productID) != nil {
                _ = try await confirmStreakRestore(
                    transaction: transaction,
                    jwsRepresentation: result.jwsRepresentation
                )
                await transaction.finish()
            }
        } catch {
            // Keep the transaction unfinished so it can be retried on the next launch.
        }
    }

}

// MARK: - Server confirmation

extension PaeoniaStoreKitService {
    /// Apple has charged the user by the time this runs. Any failure that is not
    /// already specific becomes `.serverConfirmationFailed`, so the paywall can
    /// say the payment went through and point to Restore.
    private func confirmPaidPurchase(
        transaction: Transaction,
        jwsRepresentation: String,
        priceDisplay: String?
    ) async throws {
        do {
            try await confirm(
                transaction: transaction,
                jwsRepresentation: jwsRepresentation,
                priceDisplay: priceDisplay
            )
        } catch let error as PaeoniaPurchaseError {
            throw error
        } catch {
            throw PaeoniaPurchaseError.serverConfirmationFailed(nil)
        }
    }

    private func configuredAppAccountToken() async throws -> UUID {
        guard let userID else {
            throw PaeoniaPurchaseError.userNotConfigured
        }

        if let appAccountToken {
            return appAccountToken
        }

        let client = try clientProvider.client()
        let tokenString: String = try await client.mutation(
            "access:get_or_create_app_account_token",
            args: ["p_user_id": userID]
        )

        guard let token = UUID(uuidString: tokenString) else {
            throw PaeoniaPurchaseError.invalidUserID
        }

        // A sign-out or account switch during the request must not hand the old
        // account's token to the new one.
        guard self.userID == userID else {
            throw PaeoniaPurchaseError.userNotConfigured
        }

        appAccountToken = token
        return token
    }

    private func productDisplayPrice(for productID: String) -> String? {
        products.first { $0.id == productID }?.displayPrice
    }

    private func confirm(
        transaction: Transaction,
        jwsRepresentation: String,
        priceDisplay: String?
    ) async throws {
        do {
            let client = try clientProvider.client()
            let request = PaeoniaStoreKitUploadRequest(
                jws: jwsRepresentation,
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                productId: transaction.productID,
                environment: environmentName(for: transaction),
                priceDisplay: priceDisplay
            )

            let response: PaeoniaStoreKitUploadResponse = try await client.action(
                "access:verify_purchase",
                args: request
            )

            guard response.isConfirmed else {
                throw purchaseError(fromConfirmationReason: response.error)
            }
        } catch let error as PaeoniaConvexError {
            throw purchaseError(fromConfirmationReason: Self.confirmationFailureReason(from: error))
        }
    }

    private func confirmStreakRestore(
        transaction: Transaction,
        jwsRepresentation: String
    ) async throws -> Int {
        do {
            let client = try clientProvider.client()
            let request = PaeoniaStreakRestoreUploadRequest(
                jws: jwsRepresentation,
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                productId: transaction.productID,
                environment: environmentName(for: transaction)
            )

            let response: PaeoniaStreakRestoreUploadResponse = try await client.action(
                "access:redeem_streak_restore",
                args: request
            )

            guard response.isConfirmed else {
                throw Self.streakRestoreError(fromConfirmationReason: response.error)
            }

            return response.restoredCount ?? 0
        } catch {
            throw Self.streakRestoreConfirmationError(from: error)
        }
    }

    /// Apple has charged by the time a streak restore is confirmed. Any failure
    /// that is not already specific, such as a lost connection, becomes
    /// `.serverConfirmationFailed`, so the sheet says the payment is waiting
    /// instead of offering to buy again.
    static func streakRestoreConfirmationError(from error: any Error) -> PaeoniaPurchaseError {
        if let error = error as? PaeoniaPurchaseError { return error }
        guard let error = error as? PaeoniaConvexError else { return .serverConfirmationFailed(nil) }
        return streakRestoreError(fromConfirmationReason: confirmationFailureReason(from: error))
    }

    private static func streakRestoreError(fromConfirmationReason reason: String?) -> PaeoniaPurchaseError {
        if reason == "Apple appAccountToken is not registered"
            || reason == "Apple transaction belongs to a different user" {
            return .purchaseLinkedToAnotherAccount
        }

        if reason == "No streak is available to restore" {
            return .streakNotRestorable
        }

        return .serverConfirmationFailed(reason)
    }

    private func purchaseError(fromConfirmationReason reason: String?) -> PaeoniaPurchaseError {
        if reason == "Apple appAccountToken is not registered"
            || reason == "Apple transaction belongs to a different user" {
            return .purchaseLinkedToAnotherAccount
        }

        return .serverConfirmationFailed(reason)
    }

    private func environmentName(for transaction: Transaction) -> String {
        if transaction.environment == .xcode {
            "xcode"
        } else if transaction.environment == .sandbox {
            "sandbox"
        } else {
            "production"
        }
    }

    /// The backend turns a failed purchase check into `server(code: "http_<status>",
    /// message: <reason>)`, where the message is the verifier's own reason text.
    private static func confirmationFailureReason(from error: PaeoniaConvexError) -> String {
        switch error {
        case let .server(code, message):
            if !message.isEmpty {
                return message
            }
            return "Purchase verifier returned \(code ?? "an error")."
        case let .http(status, body):
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else {
                return "Purchase verifier returned HTTP \(status)."
            }

            return "Purchase verifier returned HTTP \(status): \(trimmedBody)"
        case .notAuthenticated:
            return "Purchase verifier needs a signed-in user."
        }
    }
}
