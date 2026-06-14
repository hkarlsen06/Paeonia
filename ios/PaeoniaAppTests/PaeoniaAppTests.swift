import Testing
@testable import PaeoniaApp

struct PaeoniaAppTests {

    @MainActor
    @Test func testHarnessIsAvailable() {
        #expect(AppState.allCases == [
            .launching,
            .unauthenticated,
            .onboarding,
            .limitedAuthenticated,
            .reviewAccess,
            .unpaired,
            .invitePending,
            .paired,
            .pairedPaywalled,
            .entitlementLost,
            .entitlementRestored,
            .relationshipEndedNotice,
            .deletingAccount,
        ])
    }
}
