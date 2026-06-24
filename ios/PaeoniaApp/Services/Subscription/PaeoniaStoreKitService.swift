import Foundation
import Observation
import StoreKit
import Supabase

@MainActor
protocol PaeoniaStoreKitServicing: AnyObject {
    var products: [Product] { get }

    func configure(userID: String)
    func loadProducts() async throws
    func product(for productID: PaeoniaSubscriptionProductID) -> Product?
    func purchase(_ product: Product) async throws -> Bool
    func restorePurchases() async throws -> Bool
}

@MainActor
@Observable
final class PaeoniaStoreKitService: PaeoniaStoreKitServicing {
    static let shared = PaeoniaStoreKitService()

    private(set) var products: [Product] = []

    private let clientProvider: PaeoniaSupabaseClientProvider
    private var userID: String?
    private var appAccountToken: UUID?

    init(clientProvider: PaeoniaSupabaseClientProvider = .shared) {
        self.clientProvider = clientProvider
    }

    func configure(userID: String) {
        guard self.userID != userID else {
            return
        }

        self.userID = userID
        appAccountToken = nil
    }

    func loadProducts() async throws {
        products = try await Product.products(
            for: PaeoniaSubscriptionProductID.allCases.map(\.rawValue)
        )
    }

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? {
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
                throw PaeoniaPurchaseError.serverConfirmationFailed(response.error)
            }
        } catch let error as FunctionsError {
            throw PaeoniaPurchaseError.serverConfirmationFailed(confirmationFailureReason(from: error))
        }
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
