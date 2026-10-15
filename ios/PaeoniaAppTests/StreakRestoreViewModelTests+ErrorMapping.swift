import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
extension StreakRestoreViewModelTests {
    // MARK: - Service error mapping

    /// Apple has charged before the server step runs. A lost connection there used
    /// to read as "didn't go through" and left Buy enabled, inviting a second charge.
    @Test func lostConnectionAfterPaymentCountsAsPaidButNotConfirmed() {
        let mapped = PaeoniaStoreKitService.streakRestoreConfirmationError(from: URLError(.networkConnectionLost))

        #expect(mapped == .serverConfirmationFailed(nil))
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(from: PaeoniaPurchaseError.streakNotRestorable)
                == .streakNotRestorable
        )
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(
                from: PaeoniaConvexError.server(
                    code: "no_streak_to_restore",
                    message: "No streak is available to restore"
                )
            ) == .streakNotRestorable
        )
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(
                from: PaeoniaConvexError.server(
                    code: "purchase_linked_to_another_account",
                    message: "Apple transaction belongs to a different user"
                )
            ) == .purchaseLinkedToAnotherAccount
        )
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(
                from: PaeoniaConvexError.server(code: "purchase_not_saved", message: "Could not restore your streak")
            ) == .serverConfirmationFailed("Could not restore your streak")
        )
    }

    /// A paid restore that failed to confirm used to look the same as "nothing
    /// pending", so a reopened sheet could sell a second one.
    @Test func unconfirmedPaidRestoreIsReportedAsPending() async {
        let pending = PaeoniaStoreKitService.pendingRestoreCount(nil, afterFailure: URLError(.timedOut))
        #expect(pending == 0)
        #expect(PaeoniaStoreKitService.pendingRestoreCount(21, afterFailure: URLError(.timedOut)) == 21)
        #expect(
            PaeoniaStoreKitService.pendingRestoreCount(nil, afterFailure: PaeoniaPurchaseError.streakNotRestorable)
                == nil
        )

        // The sheet then waits for the first payment instead of buying again.
        let service = FakeStreakRestoreStoreKit(result: .success(30), recovered: pending)
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )
        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.error == .paidNotConfirmed)
        #expect(service.redeemCallCount == 0)
    }
}
