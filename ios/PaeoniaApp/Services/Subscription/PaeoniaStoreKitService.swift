import Foundation
import Observation
import StoreKit
import Supabase

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
    func purchase(_ product: Product) async throws -> Bool
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

    private let clientProvider: PaeoniaSupabaseClientProvider
    private var userID: String?
    private var appAccountToken: UUID?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    init(clientProvider: PaeoniaSupabaseClientProvider = .shared) {
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

    func purchase(_ product: Product) async throws -> Bool {
        let token = try await configuredAppAccountToken()
        let purchaseResult: Product.PurchaseResult

        do {
            purchaseResult = try await product.purchase(options: [.appAccountToken(token)])
        } catch {
            throw PaeoniaPurchaseError.purchaseFailed
        }

        switch purchaseResult {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw PaeoniaPurchaseError.verificationFailed
            }

            try await confirm(
                transaction: transaction,
                jwsRepresentation: verification.jwsRepresentation,
                priceDisplay: product.displayPrice
            )

            await transaction.finish()

            return true
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async throws -> Bool {
        let token = try await configuredAppAccountToken()
        try await AppStore.sync()

        var didConfirmPurchase = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else {
                continue
            }

            guard PaeoniaSubscriptionProductID(rawValue: transaction.productID) != nil else {
                continue
            }

            guard transaction.appAccountToken == token else {
                continue
            }

            let displayPrice = productDisplayPrice(for: transaction.productID)
            try await confirm(
                transaction: transaction,
                jwsRepresentation: result.jwsRepresentation,
                priceDisplay: displayPrice
            )
            didConfirmPurchase = true
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
        case .pending, .userCancelled:
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
                continue
            }
        }

        return recoveredCount
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

    private func configuredAppAccountToken() async throws -> UUID {
        guard let userID else {
            throw PaeoniaPurchaseError.userNotConfigured
        }

        if let appAccountToken {
            return appAccountToken
        }

        let client = try clientProvider.client()
        let tokenString: String = try await client
            .rpc("get_or_create_app_account_token", params: ["p_user_id": userID])
            .execute()
            .value

        guard let token = UUID(uuidString: tokenString) else {
            throw PaeoniaPurchaseError.invalidUserID
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

            let response: PaeoniaStoreKitUploadResponse = try await client.functions.invoke(
                "apple-verify-purchase",
                options: FunctionInvokeOptions(body: request)
            )

            guard response.isConfirmed else {
                throw purchaseError(fromConfirmationReason: response.error)
            }
        } catch let error as FunctionsError {
            throw purchaseError(fromConfirmationReason: confirmationFailureReason(from: error))
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

            let response: PaeoniaStreakRestoreUploadResponse = try await client.functions.invoke(
                "apple-redeem-streak-restore",
                options: FunctionInvokeOptions(body: request)
            )

            guard response.isConfirmed else {
                throw streakRestoreError(fromConfirmationReason: response.error)
            }

            return response.restoredCount ?? 0
        } catch let error as FunctionsError {
            throw streakRestoreError(fromConfirmationReason: confirmationFailureReason(from: error))
        }
    }

    private func streakRestoreError(fromConfirmationReason reason: String?) -> PaeoniaPurchaseError {
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

    private func confirmationFailureReason(from error: FunctionsError) -> String {
        switch error {
        case .relayError:
            return "Supabase could not reach the purchase verifier."
        case let .httpError(code, data):
            let response = try? JSONDecoder().decode(PaeoniaStoreKitUploadResponse.self, from: data)
            if let responseError = response?.error, !responseError.isEmpty {
                return responseError
            }

            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let body, !body.isEmpty else {
                return "Purchase verifier returned HTTP \(code)."
            }

            return "Purchase verifier returned HTTP \(code): \(body)"
        @unknown default:
            return "Purchase verifier failed."
        }
    }
}
