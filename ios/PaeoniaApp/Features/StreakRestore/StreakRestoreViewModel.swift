import Foundation
import Observation
import StoreKit

/// Drives the streak-restore offer: loads the consumable's price, runs the
/// purchase, and on success asks the caller to refresh the streak. Mirrors
/// `PaywallViewModel`'s shape (load products, purchase, map errors), but the
/// product is a one-time consumable and the outcome is a restored streak.
@MainActor
@Observable
final class StreakRestoreViewModel {
    let streak: CoupleStreak
    private(set) var isLoading = false
    private(set) var hasFinishedLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var error: StreakRestoreError?
    /// Set once a restore lands (via purchase or recovery). The view switches to
    /// a celebratory restored-streak state when this becomes non-nil.
    private(set) var restoredCount: Int?

    private let storeKitService: any PaeoniaStoreKitServicing
    private let onRestored: @MainActor (Int) async -> Void

    init(
        streak: CoupleStreak,
        userID: String?,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil,
        onRestored: @escaping @MainActor (Int) async -> Void = { _ in }
    ) {
        self.streak = streak
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        self.onRestored = onRestored

        if let userID {
            self.storeKitService.configure(userID: userID)
        }
    }

    /// The lost streak length being offered back — what the broken flame shows.
    var restorableCount: Int { streak.restorableCount }

    var priceText: String? {
        storeKitService.product(for: .streakRestore)?.displayPrice
    }

    private var hasLoadedProduct: Bool {
        storeKitService.product(for: .streakRestore) != nil
    }

    func load() async {
        // Re-apply any restore that was paid for but never confirmed (e.g. the
        // app died mid-flow). Idempotent on the server, so this is always safe.
        if let recovered = await storeKitService.recoverPendingStreakRestores() {
            restoredCount = recovered
            await onRestored(recovered)
            return
        }

        guard !isLoading, !hasLoadedProduct else {
            hasFinishedLoadingProducts = true
            return
        }

        isLoading = true
        do {
            try await storeKitService.loadProducts()
        } catch {
            // The price just won't show; the offer stays usable on retry.
        }
        hasFinishedLoadingProducts = true
        isLoading = false
    }

    func purchase() async -> Bool {
        isPurchasing = true
        error = nil

        do {
            // The service throws `.productUnavailable` if the consumable never
            // loaded, which maps to `.productsUnavailable` below.
            let count = try await storeKitService.redeemStreakRestore()
            isPurchasing = false

            guard let count else {
                // Cancelled or still pending — leave the offer in place.
                return false
            }

            restoredCount = count
            await onRestored(count)
            return true
        } catch let purchaseError as PaeoniaPurchaseError {
            error = Self.restoreError(for: purchaseError)
            isPurchasing = false
            return false
        } catch {
            self.error = .purchaseNotConfirmed
            isPurchasing = false
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private static func restoreError(for error: PaeoniaPurchaseError) -> StreakRestoreError {
        switch error {
        case .purchaseLinkedToAnotherAccount:
            .purchaseLinkedToAnotherAccount
        case .streakNotRestorable:
            .streakNotRestorable
        case .productUnavailable:
            .productsUnavailable
        default:
            .purchaseNotConfirmed
        }
    }
}

enum StreakRestoreError: Equatable {
    case productsUnavailable
    case purchaseNotConfirmed
    case purchaseLinkedToAnotherAccount
    case streakNotRestorable

    var message: String {
        switch self {
        case .productsUnavailable:
            String(localized: .paywallErrorProductsUnavailable)
        case .purchaseNotConfirmed:
            String(localized: .paywallErrorPurchaseNotConfirmed)
        case .purchaseLinkedToAnotherAccount:
            String(localized: .paywallErrorPurchaseLinkedToAnotherAccount)
        case .streakNotRestorable:
            String(localized: .streakRestoreErrorNotRestorable)
        }
    }
}
