import Foundation
import Observation
import StoreKit

/// Drives the streak-restore offer: loads the consumable's price, runs the
/// purchase, and on success asks the caller to refresh the streak. Mirrors
/// `PaywallViewModel`'s shape (load products, purchase, map errors), but the
/// product is a one-time consumable and the outcome is a restored streak.
///
/// The consumable is charged by Apple before the server applies it, so most of
/// the care here is about never charging twice: a restore that was paid for but
/// not confirmed yet is recovered before anything new is bought, and the buy
/// button turns into a re-check once a payment is waiting for confirmation.
@MainActor
@Observable
final class StreakRestoreViewModel {
    /// The streak as it was when the offer opened. `latestStreak` re-reads it
    /// before buying, because the partner may have restored it in the meantime.
    let streak: CoupleStreak
    private(set) var isLoading = false
    private(set) var hasFinishedLoadingProducts = false
    /// True when the last attempt to load the price failed, as opposed to still loading.
    private(set) var didPriceLoadFail = false
    private(set) var isPurchasing = false
    private(set) var error: StreakRestoreError?
    /// Set once a restore lands (via purchase or recovery). The view switches to
    /// a celebratory restored-streak state when this becomes non-nil.
    private(set) var restoredCount: Int?
    /// True after a payment that the server has not confirmed yet. Buying again
    /// would charge a second time, so the button only re-checks the first one.
    private(set) var isAwaitingConfirmation = false
    /// Why nothing more can be bought here (the streak is back, the time ran out,
    /// or a payment already went through). Buying again would only charge again.
    private(set) var blockingError: StreakRestoreError?

    private let storeKitService: any PaeoniaStoreKitServicing
    private let onRestored: @MainActor (Int) async -> Void
    private let latestStreak: (@MainActor () async -> CoupleStreak?)?

    /// - Parameter latestStreak: Reads the couple's current streak. Called right
    ///   before a purchase so a stale sheet cannot sell a restore that is no longer
    ///   possible. Return `nil` when the streak could not be read; the purchase
    ///   then goes ahead and the server has the final say.
    init(
        streak: CoupleStreak,
        userID: String?,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil,
        onRestored: @escaping @MainActor (Int) async -> Void = { _ in },
        latestStreak: (@MainActor () async -> CoupleStreak?)? = nil
    ) {
        self.streak = streak
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        self.onRestored = onRestored
        self.latestStreak = latestStreak

        if let userID {
            self.storeKitService.configure(userID: userID)
        }
    }

    /// The lost streak length being offered back, which the broken flame shows.
    var restorableCount: Int { streak.restorableCount }

    var priceText: String? {
        storeKitService.product(for: .streakRestore)?.displayPrice
    }

    /// True when the price could not be loaded, so the button should offer a reload.
    var needsPriceRetry: Bool {
        didPriceLoadFail && !isLoading && !isAwaitingConfirmation
    }

    private var hasLoadedProduct: Bool {
        storeKitService.product(for: .streakRestore) != nil
    }

    func load() async {
        // Re-apply any restore that was paid for but never confirmed (e.g. the
        // app died mid-flow). Idempotent on the server, so this is always safe.
        if let recovered = await recoverPendingRestore() {
            await finishRestore(recovered)
            return
        }

        guard !isLoading else { return }
        if case .productsUnavailable = error {
            error = nil
        }

        if let failure = await loadProductIfNeeded() {
            error = .productsUnavailable(failure)
        }
    }

    func purchase() async -> Bool {
        guard !isPurchasing else { return false }
        if let blockingError {
            error = blockingError
            return false
        }

        isPurchasing = true
        error = nil
        let count = await recoverOrBuy()
        isPurchasing = false

        guard let count else { return false }
        await finishRestore(count)
        return true
    }

    func clearError() {
        error = nil
    }

    /// The restored length, or `nil` when nothing came back. `error` says why,
    /// except when the user cancelled or the App Store is still waiting on approval.
    private func recoverOrBuy() async -> Int? {
        // A restore paid for earlier must land before anything is bought again.
        if let recovered = await recoverPendingRestore() {
            return recovered
        }
        if isAwaitingConfirmation {
            record(.paidNotConfirmed)
            return nil
        }

        if let reason = await reasonStreakIsNoLongerRestorable() {
            record(reason)
            return nil
        }

        // Normally loaded already. If the first load failed, one more try here.
        if let failure = await loadProductIfNeeded() {
            record(.productsUnavailable(failure))
            return nil
        }

        do {
            // The service throws `.productUnavailable` if the consumable never
            // loaded, which maps to `.productsUnavailable` below.
            guard let count = try await storeKitService.redeemStreakRestore() else {
                // Cancelled or still pending. Leave the offer in place.
                return nil
            }
            guard count > 0 else {
                // Apple charged but the server did not report a streak length.
                record(.paidNotConfirmed)
                return nil
            }
            return count
        } catch let purchaseError as PaeoniaPurchaseError {
            record(Self.restoreError(for: purchaseError))
            return nil
        } catch {
            record(.purchaseNotConfirmed)
            return nil
        }
    }

    /// Returns the length of a restore that was paid for earlier and is now applied.
    /// A recovered length of 0 means the payment went through but the streak did not
    /// come back, which is reported as a payment waiting for confirmation.
    private func recoverPendingRestore() async -> Int? {
        guard let recovered = await storeKitService.recoverPendingStreakRestores() else {
            return nil
        }
        guard recovered > 0 else {
            record(.paidNotConfirmed)
            return nil
        }
        return recovered
    }

    private func finishRestore(_ count: Int) async {
        isAwaitingConfirmation = false
        error = nil
        restoredCount = count
        await onRestored(count)
    }

    /// Loads the price once if it is missing. Returns why loading failed, or nil
    /// when the price is there or another load is running.
    private func loadProductIfNeeded() async -> PaeoniaFailure? {
        if hasLoadedProduct {
            didPriceLoadFail = false
            hasFinishedLoadingProducts = true
            return nil
        }
        guard !isLoading else { return nil }

        isLoading = true
        defer {
            isLoading = false
            hasFinishedLoadingProducts = true
        }
        do {
            try await storeKitService.loadProducts()
            didPriceLoadFail = false
            return nil
        } catch {
            didPriceLoadFail = true
            return PaeoniaFailure(error)
        }
    }

    private func reasonStreakIsNoLongerRestorable() async -> StreakRestoreError? {
        guard let latestStreak, let latest = await latestStreak() else { return nil }

        if latest.isRestorable { return nil }

        // A restore leaves the streak at or above the length that was offered.
        let isBackAlready = streak.restorableCount > 0 && latest.currentCount >= streak.restorableCount
        return isBackAlready ? .streakAlreadyBack : .streakExpired
    }

    private func record(_ restoreError: StreakRestoreError) {
        error = restoreError
        switch restoreError {
        case .paidNotConfirmed:
            isAwaitingConfirmation = true
        case .streakNotRestorable, .purchaseLinkedToAnotherAccount, .streakAlreadyBack, .streakExpired,
             .waitingForApproval:
            // A purchase waiting for approval would only send a second request.
            blockingError = restoreError
        case .productsUnavailable, .purchaseNotConfirmed:
            break
        }
    }

    private static func restoreError(for error: PaeoniaPurchaseError) -> StreakRestoreError {
        switch error {
        case .purchaseLinkedToAnotherAccount:
            .purchaseLinkedToAnotherAccount
        case .streakNotRestorable:
            .streakNotRestorable
        case .productUnavailable:
            .productsUnavailable(.other)
        case .serverConfirmationFailed:
            // Apple already charged; only the server step failed. The unfinished
            // purchase is retried on the next launch and the next time this opens.
            .paidNotConfirmed
        case .pendingApproval:
            .waitingForApproval
        default:
            .purchaseNotConfirmed
        }
    }
}

enum StreakRestoreError: Equatable {
    case productsUnavailable(PaeoniaFailure)
    /// The purchase did not go through and nothing was charged.
    case purchaseNotConfirmed
    case purchaseLinkedToAnotherAccount
    /// Apple charged, but the server could not bring the streak back in time.
    case streakNotRestorable
    /// Apple charged, but the server has not confirmed the restore yet.
    case paidNotConfirmed
    /// Found before buying: the partner already brought the streak back.
    case streakAlreadyBack
    /// Found before buying: the time to bring the streak back has passed.
    case streakExpired
    /// Ask to Buy: the purchase waits for approval. Nothing is charged until then.
    case waitingForApproval

    var message: String {
        switch self {
        case let .productsUnavailable(failure):
            // Only a phone without a connection is told to check it.
            String(localized: failure == .offline ? .streakRestoreErrorPriceUnavailable : .commonLoadFailedMessage)
        case .purchaseNotConfirmed:
            String(localized: .streakRestoreErrorPurchaseNotCompleted)
        case .purchaseLinkedToAnotherAccount:
            String(localized: .paywallErrorPurchaseLinkedToAnotherAccount)
        case .streakNotRestorable:
            String(localized: .streakRestoreErrorNotRestorable)
        case .paidNotConfirmed:
            String(localized: .streakRestoreErrorPaidNotConfirmed)
        case .streakAlreadyBack:
            String(localized: .streakRestoreErrorAlreadyBack)
        case .streakExpired:
            String(localized: .streakRestoreExpiredMessage)
        case .waitingForApproval:
            String(localized: .streakRestorePendingApprovalMessage)
        }
    }
}
